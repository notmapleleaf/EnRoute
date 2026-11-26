import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/geo.dart';
import '../core/placement.dart';
import '../state/enroute_controller.dart';
import 'place_widgets.dart';

/// Full-screen map in "drive mode": the map turns so the road ahead points up,
/// you sit in the lower part of the screen, and the zoom adapts so the stops
/// being shown fit in view.
///
/// Uses OpenStreetMap tiles so it works without a map key. To switch to the
/// Google Maps SDK later, replace this widget; nothing else depends on it.
class EnRouteMap extends StatefulWidget {
  const EnRouteMap({super.key});

  @override
  State<EnRouteMap> createState() => _EnRouteMapState();
}

class _EnRouteMapState extends State<EnRouteMap> {
  static const LatLng _fallbackCenter = LatLng(10.5, 76.2);
  static bool _tileErrorLogged = false;

  /// Map rotation applied per degree of heading. -1 turns the map so the
  /// direction of travel is at the top of the screen. If the road ahead ever
  /// points DOWN on your phone instead, change this to 1.
  static const double _rotationSign = -1;

  /// Metres per pixel at zoom 0 on the equator (256 px tiles).
  static const double _worldMetresPerPixel = 156543.03392;

  final _map = MapController();
  String? _cameraKey;

  /// Built once and reused. Creating a new TileLayer on every rebuild gives it
  /// a new tile loader each time, which cancels tiles still downloading and
  /// leaves grey patches until the map is moved.
  final TileLayer _tiles = TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.enroute.app',
    // Load an extra ring of tiles around the screen so a turned map (and the
    // jump to a new zoom) has less blank edge.
    panBuffer: 2,
    errorTileCallback: (tile, error, stackTrace) {
      // Logged once so a blank grey map can be diagnosed from the console.
      if (_tileErrorLogged) return;
      _tileErrorLogged = true;
      debugPrint('Map tile failed to load: $error');
    },
  );

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Re-frames the camera when something it should show has changed: a GPS
  /// move, a new route, a new set of stops, or the recentre button. Does
  /// nothing while the user is panning the map by hand.
  void _syncCamera(EnRouteController c) {
    final user = c.userPosition;
    if (user == null) return;
    final route = c.route;
    final results = c.results;

    // While following, a GPS move counts as a change; while panning it doesn't.
    final followPart = c.following
        ? '${user.latitude.toStringAsFixed(4)},${user.longitude.toStringAsFixed(4)}'
        : 'free';
    final ids = results.map((p) => p.id).join(',');
    final key = '${route?.hashCode}|${c.category?.name}|$ids|'
        '${c.recenterTick}|$followPart';
    if (key == _cameraKey) return;
    _cameraKey = key;
    if (!c.following) return;

    // No trip yet: just show where the user is, north up.
    if (route == null) {
      _map.moveAndRotate(user, 14.5, 0);
      return;
    }

    final heading = c.heading ?? 0;
    final size = MediaQuery.sizeOf(context);

    // How far ahead we want to see: the farthest stop shown, or a few km of
    // road when there are none.
    var reach = 6000.0;
    if (results.isNotEmpty) {
      reach = 3000;
      for (final p in results) {
        reach = math.max(reach, haversineMeters(user, p.location));
      }
    }

    // Pick a zoom so `reach` fills the usable part of the screen (the top
    // quarter is covered by the floating panel).
    final cosLat = math.cos(user.latitude * math.pi / 180);
    final wantedMpp = reach * 1.2 / (size.height * 0.45);
    var zoom = math.log(_worldMetresPerPixel * cosLat / wantedMpp) / math.ln2;
    zoom = zoom.clamp(8.0, 16.0);

    // Put the user low on the screen, like navigation apps do: aim the map
    // centre ahead of them along the heading.
    final mpp = _worldMetresPerPixel * cosLat / math.pow(2, zoom);
    final centre = destinationPoint(user, heading, size.height * 0.22 * mpp);
    _map.moveAndRotate(centre, zoom, _rotationSign * heading);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EnRouteController>();
    final route = c.route;
    final user = c.userPosition;
    final results = c.results;
    final selected = c.selected;
    final heading = c.heading;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCamera(c);
    });

    // High-contrast route: vivid blue with a white casing so it stands out
    // from yellow/white/orange roads. The part already driven goes grey.
    final polylines = <Polyline>[];
    if (route != null) {
      final passed = slicePolyline(route.points, 0, c.userAlongMeters);
      final ahead = slicePolyline(
        route.points,
        c.userAlongMeters,
        c.routeLengthMeters,
      );
      if (passed.length >= 2) {
        polylines.add(Polyline(
          points: passed,
          strokeWidth: 6,
          color: const Color(0xFF9E9E9E),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ));
      }
      if (ahead.length >= 2) {
        polylines.add(Polyline(
          points: ahead,
          strokeWidth: 8,
          color: const Color(0xFF2962FF),
          borderStrokeWidth: 3,
          borderColor: Colors.white,
        ));
      }
    }

    final markers = <Marker>[
      if (route != null)
        Marker(
          point: route.destination,
          width: 40,
          height: 40,
          rotate: true,
          child: const Icon(Icons.flag, color: Colors.black87, size: 34),
        ),
      if (route != null)
        for (var i = 0; i < results.length; i++)
          Marker(
            point: results[i].location,
            width: PlaceMarker.boxWidth,
            height: PlaceMarker.boxHeight,
            // Keep pins and cards upright on screen while the map turns.
            rotate: true,
            child: PlaceMarker(
              place: results[i],
              ahead: c.distanceAhead(results[i]),
              side: cardSideFor(
                route,
                results[i],
                i,
                headingDeg: heading ?? 0,
              ),
              selected: selected?.id == results[i].id,
              onTap: () => c.select(results[i]),
            ),
          ),
      // Not counter-rotated: the arrow is drawn at the heading in map space, so
      // it points up on screen when the map is turned to face the way you go.
      if (user != null)
        Marker(
          point: user,
          width: 44,
          height: 44,
          child: _UserMarker(headingDeg: heading),
        ),
    ];

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: user ?? _fallbackCenter,
        initialZoom: user != null ? 14 : 6,
        onTap: (_, __) => c.select(null),
        onPositionChanged: (camera, hasGesture) {
          // The user moved the map by hand: stop auto-following until they
          // tap the recentre button.
          if (hasGesture) context.read<EnRouteController>().stopFollowing();
        },
      ),
      children: [
        _tiles,
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// The user's position: a navigation arrow showing which way they're heading,
/// or a plain blue dot when there is no trip (so no known direction).
class _UserMarker extends StatelessWidget {
  const _UserMarker({this.headingDeg});

  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    final heading = headingDeg;
    if (heading == null) {
      return Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
        ),
      );
    }
    return Transform.rotate(
      angle: heading * math.pi / 180,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 5)],
        ),
        child: const Icon(
          Icons.navigation,
          color: Color(0xFF0B2A6F),
          size: 32,
        ),
      ),
    );
  }
}
