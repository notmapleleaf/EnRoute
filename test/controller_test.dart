import 'dart:async';

import 'package:enroute/core/geo.dart';
import 'package:enroute/models/models.dart';
import 'package:enroute/services/mock_services.dart';
import 'package:enroute/services/services.dart';
import 'package:enroute/state/enroute_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _CountingPlaces implements PlacesService {
  _CountingPlaces(this.inner);
  final PlacesService inner;
  int calls = 0;

  @override
  Future<List<Place>> searchAhead({
    required RouteData route,
    required LatLng from,
    required double fromAlongMeters,
    required double toAlongMeters,
    required PlaceCategory category,
  }) {
    calls++;
    return inner.searchAhead(
      route: route,
      from: from,
      fromAlongMeters: fromAlongMeters,
      toAlongMeters: toAlongMeters,
      category: category,
    );
  }
}

/// A GPS we can move by hand.
class _FakeLocation implements LocationService {
  _FakeLocation(this.start);
  final LatLng start;
  final moves = StreamController<LatLng>.broadcast();

  @override
  Future<LatLng> currentPosition() async => start;

  @override
  Stream<LatLng> positionUpdates() => moves.stream;
}

class _BrokenLocation implements LocationService {
  @override
  Future<LatLng> currentPosition() async =>
      throw EnRouteException('Location is turned off.');

  @override
  Stream<LatLng> positionUpdates() => const Stream<LatLng>.empty();
}

Future<EnRouteController> _ready({
  _CountingPlaces? places,
  LocationService? location,
  OpenInMaps? open,
  String destination = 'Kozhikode',
}) async {
  final c = EnRouteController(
    routes: MockRoutesService(),
    places: places ?? _CountingPlaces(MockPlacesService()),
    location: location ?? MockLocationService(),
    openInMaps: open,
  );
  await c.init();
  await c.setDestination(destination);
  return c;
}

void main() {
  test('init finds the user; a broken GPS reports a readable error', () async {
    final ok = EnRouteController(
      routes: MockRoutesService(),
      places: MockPlacesService(),
      location: MockLocationService(),
    );
    await ok.init();
    expect(ok.userPosition, MockLocationService.start);
    expect(ok.error, isNull);

    final bad = EnRouteController(
      routes: MockRoutesService(),
      places: MockPlacesService(),
      location: _BrokenLocation(),
    );
    await bad.init();
    expect(bad.userPosition, isNull);
    expect(bad.locationFailed, isTrue);
    expect(bad.error, isNotNull);
  });

  test('route starts at the user and goes to either end of the sample road',
      () async {
    final toKozhikode = await _ready(destination: 'Kozhikode');
    expect(toKozhikode.route, isNotNull);
    expect(toKozhikode.route!.destinationLabel, 'Kozhikode');
    expect(
      haversineMeters(toKozhikode.route!.origin, MockLocationService.start),
      lessThan(500),
    );

    final toKochi = await _ready(destination: 'Kochi');
    expect(toKochi.route!.destinationLabel, 'Kochi');
  });

  test('bad or empty destination sets an error and no route', () async {
    final c = await _ready(destination: 'Paris');
    expect(c.error, isNotNull);
    expect(c.route, isNull);

    await c.setDestination('   ');
    expect(c.error, isNotNull);
    expect(c.route, isNull);
  });

  test('shows only a few stops, all ahead of the user, nearest first',
      () async {
    final c = await _ready();
    await c.selectCategory(PlaceCategory.restaurant);

    final r = c.results;
    expect(r, isNotEmpty);
    expect(r.length, lessThanOrEqualTo(EnRouteController.maxShown));
    for (final p in r) {
      expect(c.distanceAhead(p), greaterThanOrEqualTo(-150));
      expect(c.distanceAhead(p),
          lessThanOrEqualTo(EnRouteController.defaultLookAheadMeters + 150));
      expect(p.detourMeters, greaterThan(0));
    }
    for (var i = 1; i < r.length; i++) {
      expect(c.distanceAhead(r[i]),
          greaterThanOrEqualTo(c.distanceAhead(r[i - 1])));
    }
  });

  test('stops behind the user are not offered', () async {
    // Heading to Kozhikode from Chavakkad, Kaipamangalam (r3) is behind us.
    final c = await _ready();
    await c.selectCategory(PlaceCategory.restaurant);
    expect(c.results.any((p) => p.id == 'r3'), isFalse);

    // Heading to Kochi it is ahead of us.
    final back = await _ready(destination: 'Kochi');
    await back.selectCategory(PlaceCategory.restaurant);
    expect(back.results.any((p) => p.id == 'r3'), isTrue);
  });

  test('sorting by rating puts best-rated first, unrated last', () async {
    final c = await _ready();
    await c.selectCategory(PlaceCategory.restaurant);
    c.setSort(SortMode.rating);

    final rated = c.results.where((p) => p.rating != null).toList();
    for (var i = 1; i < rated.length; i++) {
      expect(rated[i].rating!, lessThanOrEqualTo(rated[i - 1].rating!));
    }
  });

  test('Look further moves on to the next stretch of road, Nearer goes back',
      () async {
    const step = EnRouteController.defaultLookAheadMeters;
    final c = await _ready();
    await c.selectCategory(PlaceCategory.fuel);
    final near = c.results.map((p) => p.id).toSet();
    expect(near, isNotEmpty);
    expect(c.canLookFurther, isTrue);
    expect(c.canLookNearer, isFalse);

    await c.lookFurther();
    expect(c.lookFromMeters, step);
    expect(c.lookAheadMeters, step * 2);
    expect(c.canLookNearer, isTrue);

    // Only stops in the new 30-60 km band, none repeated from the first one.
    final far = c.results;
    expect(far, isNotEmpty);
    for (final p in far) {
      expect(near.contains(p.id), isFalse);
      expect(c.distanceAhead(p), greaterThanOrEqualTo(step - 150));
      expect(c.distanceAhead(p), lessThanOrEqualTo(step * 2 + 150));
    }

    await c.lookNearer();
    expect(c.lookFromMeters, 0);
    expect(c.lookAheadMeters, step);
    expect(c.results.map((p) => p.id).toSet(), near);
  });

  test('heading follows the road ahead and follow mode can be toggled',
      () async {
    final c = await _ready(destination: 'Kozhikode');
    // The sample road from Chavakkad to Kozhikode runs north-ish.
    expect(c.heading, isNotNull);
    expect(c.heading!, anyOf(inInclusiveRange(0, 80), inInclusiveRange(280, 360)));
    expect(c.following, isTrue);

    c.stopFollowing();
    expect(c.following, isFalse);
    c.recenter();
    expect(c.following, isTrue);

    c.clearRoute();
    expect(c.heading, isNull);
  });

  test('switching category keeps the route and searches again', () async {
    final places = _CountingPlaces(MockPlacesService());
    final c = await _ready(places: places);
    final route = c.route;

    await c.selectCategory(PlaceCategory.fuel);
    await c.selectCategory(PlaceCategory.atm);
    expect(identical(c.route, route), isTrue);
    expect(places.calls, 2);

    // Tapping the active chip again clears the category.
    await c.selectCategory(PlaceCategory.atm);
    expect(c.category, isNull);
    expect(c.results, isEmpty);
  });

  test('driving forward updates progress and drops stops once passed',
      () async {
    final gps = _FakeLocation(MockLocationService.start);
    final c = await _ready(location: gps);
    await c.selectCategory(PlaceCategory.restaurant);

    // r2 (Ponnani) is about 24 km ahead of the starting point.
    final target = c.results.firstWhere((p) => p.id == 'r2');
    final aheadBefore = c.distanceAhead(target);

    // Move the user 3 km along the route.
    final moved = slicePolyline(c.route!.points, 0, 3000).last;
    gps.moves.add(moved);
    await Future<void>.delayed(Duration.zero);

    expect(c.userAlongMeters, closeTo(3000, 50));
    expect(c.distanceAhead(target), closeTo(aheadBefore - 3000, 60));
    expect(c.results.any((p) => p.id == target.id), isTrue);

    // Drive on past that stop: it should no longer be offered.
    final past = slicePolyline(
      c.route!.points,
      0,
      target.alongRouteMeters + 500,
    ).last;
    gps.moves.add(past);
    await Future<void>.delayed(Duration.zero);
    expect(c.results.any((p) => p.id == target.id), isFalse);
  });

  test('ending the trip returns to the start state', () async {
    final c = await _ready();
    await c.selectCategory(PlaceCategory.fuel);
    c.clearRoute();
    expect(c.route, isNull);
    expect(c.destination, isNull);
    expect(c.category, isNull);
    expect(c.results, isEmpty);
    expect(c.userPosition, isNotNull); // we still know where the user is
  });

  test('addSelectedToRoute hands the selected stop to the launcher', () async {
    RouteData? gotRoute;
    Place? gotStop;
    final c = await _ready(open: (r, s) async {
      gotRoute = r;
      gotStop = s;
      return true;
    });
    await c.selectCategory(PlaceCategory.fuel);
    c.select(c.results.first);
    await c.addSelectedToRoute();

    expect(gotRoute, same(c.route));
    expect(gotStop?.id, c.results.first.id);
    expect(c.error, isNull);
  });

  test('launcher failure surfaces an error', () async {
    final c = await _ready(open: (_, __) async => false);
    await c.selectCategory(PlaceCategory.fuel);
    c.select(c.results.first);
    await c.addSelectedToRoute();
    expect(c.error, isNotNull);
  });
}
