import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/services.dart';

typedef OpenInMaps = Future<bool> Function(RouteData route, Place stop);

/// Journey-mode state: where the user is, where they're headed, and the few
/// stops just ahead of them.
///
/// The user is assumed to be travelling already, so the route always starts
/// at their current position. Only the stretch of road immediately ahead is
/// searched, and only the nearest few stops are shown.
class EnRouteController extends ChangeNotifier {
  EnRouteController({
    required RoutesService routes,
    required PlacesService places,
    required LocationService location,
    OpenInMaps? openInMaps,
    DateTime Function()? now,
  })  : _routes = routes,
        _places = places,
        _location = location,
        _openInMaps = openInMaps ?? MapsLauncher.open,
        _now = now ?? DateTime.now;

  /// How far ahead of the user we search by default.
  static const double defaultLookAheadMeters = 30000;

  /// How much "Look further" adds.
  static const double lookAheadStepMeters = 30000;

  /// How many floating cards we show at once.
  static const int maxShown = 4;

  /// Beyond this distance from the route we assume the user left it.
  static const double offRouteMeters = 400;

  /// A stop this far behind the user still counts as "right here".
  static const double passedMarginMeters = 150;

  final RoutesService _routes;
  final PlacesService _places;
  final LocationService _location;
  final OpenInMaps _openInMaps;
  final DateTime Function() _now;

  // Where the user is.
  LatLng? userPosition;
  bool locating = false;
  bool locationFailed = false;

  // The journey.
  String? destination;
  RouteData? route;
  double userAlongMeters = 0;
  double _routeLength = 0;

  // The search.
  PlaceCategory? category;
  SortMode sort = SortMode.nearest;

  /// Far edge of the searched band, measured ahead of the user.
  double lookAheadMeters = defaultLookAheadMeters;

  /// Near edge of the searched band, measured ahead of the user. 0 means
  /// "right here"; "Look further" moves the whole band on (30-60 km ahead...).
  double lookFromMeters = 0;

  Place? selected;
  List<Place> _found = const [];
  double _searchAnchor = 0;

  // The stretch of route (from the route's start) the current results cover.
  double _bandFrom = 0;
  double _bandTo = 0;

  /// Direction of travel along the road ahead, in degrees clockwise from north.
  double? _heading;

  /// Whether the map follows the user (and turns to face the way they're
  /// heading). Turned off when the user pans or zooms the map by hand.
  bool following = true;

  bool loadingRoute = false;
  bool loadingPlaces = false;
  String? error;

  /// Bumped to ask the map to re-centre on the user and the stops ahead.
  int recenterTick = 0;

  StreamSubscription<LatLng>? _sub;
  int _routeToken = 0;
  int _searchToken = 0;
  bool _rerouting = false;
  DateTime? _lastReroute;
  bool _disposed = false;

  double get routeLengthMeters => _routeLength;

  /// Which way the user is heading (degrees clockwise from north), or null
  /// when there is no route.
  double? get heading => _heading;

  double get remainingMeters => math.max(0.0, _routeLength - userAlongMeters);

  double get remainingSeconds {
    final r = route;
    if (r == null || _routeLength == 0) return 0.0;
    return r.durationSeconds * remainingMeters / _routeLength;
  }

  /// True when there is more road beyond the band we searched.
  bool get canLookFurther =>
      route != null && userAlongMeters + lookAheadMeters < _routeLength - 1;

  /// True when we've moved past the nearest band and can step back.
  bool get canLookNearer => lookFromMeters > 0;

  /// How far ahead of the user [p] is along the route (negative = passed).
  double distanceAhead(Place p) => p.alongRouteMeters - userAlongMeters;

  /// The nearest few stops ahead for the active category, de-duplicated and
  /// ordered by the chosen sort.
  List<Place> get results {
    if (route == null || category == null) return const [];

    final seen = <String>{};
    final list = <Place>[];
    for (final p in _found) {
      if (!seen.add(p.id)) continue;
      final along = p.alongRouteMeters;
      if (along < userAlongMeters - passedMarginMeters) continue; // behind us
      // Only the band we searched (absolute positions along the route, so the
      // band stays put as the user drives).
      if (along < _bandFrom - passedMarginMeters) continue;
      if (along > _bandTo + passedMarginMeters) continue;
      list.add(p);
    }

    switch (sort) {
      case SortMode.nearest:
        list.sort((a, b) => distanceAhead(a).compareTo(distanceAhead(b)));
      case SortMode.detourTime:
        list.sort((a, b) => a.detourSeconds.compareTo(b.detourSeconds));
      case SortMode.rating:
        // Unrated places sink to the bottom.
        list.sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
    }
    return list.take(maxShown).toList();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- location

  /// Gets the user's position and starts following it.
  Future<void> init() async {
    locating = true;
    locationFailed = false;
    error = null;
    notifyListeners();

    try {
      userPosition = await _location.currentPosition();
      _sub ??= _location.positionUpdates().listen(
            _onPosition,
            onError: (Object _) {}, // keep the last known position
          );
    } on EnRouteException catch (e) {
      error = e.message;
      locationFailed = true;
    } catch (e) {
      debugPrint('Location error: $e');
      error = 'Could not get your location ($e). Please try again.';
      locationFailed = true;
    }
    locating = false;
    notifyListeners();
  }

  void _onPosition(LatLng p) {
    userPosition = p;
    final r = route;
    if (r != null) {
      final proj = nearestOnPolyline(r.points, p);
      if (proj.distanceToRouteMeters > offRouteMeters) {
        _maybeReroute();
      } else {
        userAlongMeters = proj.alongRouteMeters;
        _updateHeading();
        final s = selected;
        if (s != null && distanceAhead(s) < -passedMarginMeters) {
          selected = null;
        }
        // Refresh the search once we've driven a good part of the stretch.
        if (category != null &&
            !loadingPlaces &&
            (userAlongMeters - _searchAnchor).abs() > lookAheadMeters * 0.4) {
          unawaited(_refreshSearch());
        }
      }
    }
    notifyListeners();
  }

  void _maybeReroute() {
    final dest = destination;
    final from = userPosition;
    if (dest == null || from == null || _rerouting) return;
    final now = _now();
    final last = _lastReroute;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastReroute = now;
    _rerouting = true;
    unawaited(_reroute(dest, from));
  }

  Future<void> _reroute(String dest, LatLng from) async {
    try {
      final r = await _routes.computeRoute(origin: from, destination: dest);
      if (destination != dest) return; // trip ended or changed meanwhile
      _applyRoute(r);
      notifyListeners();
      if (category != null) await _refreshSearch();
    } catch (_) {
      // Keep the old route; we'll retry on the next position update.
    } finally {
      _rerouting = false;
    }
  }

  // ----------------------------------------------------------------- journey

  void _applyRoute(RouteData r) {
    route = r;
    _routeLength = polylineLengthMeters(r.points);
    userAlongMeters = 0;
    selected = null;
    _found = const [];
    _searchAnchor = 0;
    _bandFrom = 0;
    _bandTo = 0;
    _updateHeading();
  }

  /// Works out which way the road runs just ahead of the user.
  void _updateHeading() {
    final r = route;
    if (r == null) {
      _heading = null;
      return;
    }
    final ahead = slicePolyline(
      r.points,
      userAlongMeters,
      math.min(userAlongMeters + 500, _routeLength),
    );
    // Near the very end there may be nothing ahead: keep the last heading.
    if (ahead.length >= 2) {
      _heading = bearingDegrees(ahead.first, ahead.last);
    }
  }

  /// Plans the trip from the user's current position to [text].
  Future<void> setDestination(String text) async {
    final dest = text.trim();
    if (dest.isEmpty) {
      error = 'Enter a destination.';
      notifyListeners();
      return;
    }

    var from = userPosition;
    if (from == null) {
      await init();
      from = userPosition;
      if (from == null) return; // init() already set the error
    }

    final token = ++_routeToken;
    _searchToken++; // invalidate in-flight searches for the old route
    loadingRoute = true;
    loadingPlaces = false;
    error = null;
    notifyListeners();

    try {
      final r = await _routes.computeRoute(origin: from, destination: dest);
      if (token != _routeToken) return;
      destination = dest;
      lookAheadMeters = defaultLookAheadMeters;
      lookFromMeters = 0;
      following = true;
      _applyRoute(r);
    } on EnRouteException catch (e) {
      if (token != _routeToken) return;
      error = e.message;
    } catch (_) {
      if (token != _routeToken) return;
      error = 'Something went wrong finding the route. Please try again.';
    }
    loadingRoute = false;
    recenterTick++;
    notifyListeners();

    // Keep the active category when the route changes.
    if (error == null && category != null) {
      await _refreshSearch();
    }
  }

  /// Ends the trip and returns to the "Where to?" state.
  void clearRoute() {
    _routeToken++;
    _searchToken++;
    destination = null;
    route = null;
    _routeLength = 0;
    userAlongMeters = 0;
    category = null;
    selected = null;
    _found = const [];
    _heading = null;
    following = true;
    lookAheadMeters = defaultLookAheadMeters;
    lookFromMeters = 0;
    loadingRoute = false;
    loadingPlaces = false;
    error = null;
    recenterTick++;
    notifyListeners();
  }

  // ------------------------------------------------------------------ search

  /// Selects a category (or clears it when tapped again).
  Future<void> selectCategory(PlaceCategory? next) async {
    if (next == category) next = null;
    category = next;
    selected = null;
    error = null;
    lookAheadMeters = defaultLookAheadMeters;
    lookFromMeters = 0;
    following = true;
    _found = const [];
    _searchToken++;
    loadingPlaces = false;
    notifyListeners();
    if (next != null && route != null) {
      await _refreshSearch();
    }
  }

  /// Moves on to the next band of road: after 0-30 km, shows 30-60 km, etc.
  Future<void> lookFurther() async {
    if (!canLookFurther) return;
    lookFromMeters = lookAheadMeters;
    lookAheadMeters += lookAheadStepMeters;
    selected = null;
    following = true;
    notifyListeners();
    await _refreshSearch();
  }

  /// Steps back to the previous (nearer) band.
  Future<void> lookNearer() async {
    if (!canLookNearer) return;
    lookAheadMeters = lookFromMeters;
    lookFromMeters = math.max(0.0, lookFromMeters - lookAheadStepMeters);
    selected = null;
    following = true;
    notifyListeners();
    await _refreshSearch();
  }

  Future<void> _refreshSearch() async {
    final r = route;
    final c = category;
    final from = userPosition;
    if (r == null || c == null || from == null) return;

    final token = ++_searchToken;
    final anchor = userAlongMeters;
    final bandFrom = math.min(anchor + lookFromMeters, _routeLength);
    final bandTo = math.min(anchor + lookAheadMeters, _routeLength);
    loadingPlaces = true;
    notifyListeners();

    try {
      final found = await _places.searchAhead(
        route: r,
        from: from,
        fromAlongMeters: bandFrom,
        toAlongMeters: bandTo,
        category: c,
      );
      if (token != _searchToken) return;
      _found = found;
      _searchAnchor = anchor;
      _bandFrom = bandFrom;
      _bandTo = bandTo;
    } on EnRouteException catch (e) {
      if (token != _searchToken) return;
      error = e.message;
    } catch (_) {
      if (token != _searchToken) return;
      error = 'Something went wrong searching for places. Please try again.';
    }
    loadingPlaces = false;
    notifyListeners();
  }

  // --------------------------------------------------------------- selection

  void setSort(SortMode mode) {
    if (mode == sort) return;
    sort = mode;
    notifyListeners();
  }

  void select(Place? place) {
    selected = place;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Snap the map back onto the user and the road ahead.
  void recenter() {
    following = true;
    recenterTick++;
    notifyListeners();
  }

  /// Called when the user pans or zooms the map by hand.
  void stopFollowing() {
    if (!following) return;
    following = false;
    notifyListeners();
  }

  /// Opens Google Maps with the selected stop as a waypoint.
  Future<void> addSelectedToRoute() async {
    final r = route;
    final s = selected;
    if (r == null || s == null) return;
    final ok = await _openInMaps(r, s);
    if (!ok) {
      error = 'Could not open Google Maps on this device.';
      notifyListeners();
    }
  }
}
