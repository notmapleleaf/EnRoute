import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/models.dart';
import 'services.dart';

/// Approximate Kochi -> Kozhikode road shape (coastal NH66 corridor).
/// Sample data only; the real route comes from the Routes API.
const List<LatLng> _kochiToKozhikode = [
  LatLng(9.9312, 76.2673), // Kochi
  LatLng(10.0261, 76.3125), // Edappally
  LatLng(10.1470, 76.2250), // North Paravur
  LatLng(10.2260, 76.1950), // Kodungallur
  LatLng(10.3800, 76.1150),
  LatLng(10.5780, 76.0210), // Chavakkad
  LatLng(10.7670, 75.9250), // Ponnani
  LatLng(10.8450, 76.0300), // Kuttippuram
  LatLng(10.9970, 76.0010), // Kottakkal
  LatLng(11.0500, 75.8590), // Parappanangadi
  LatLng(11.1700, 75.8650), // Ramanattukara
  LatLng(11.2588, 75.7804), // Kozhikode
];

/// Pretends to be the user's GPS, standing on the road at Chavakkad.
class MockLocationService implements LocationService {
  static const LatLng start = LatLng(10.5780, 76.0210);

  @override
  Future<LatLng> currentPosition() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return start;
  }

  @override
  Stream<LatLng> positionUpdates() => const Stream<LatLng>.empty();
}

/// Routes from the user's position to Kochi or Kozhikode along the sample road.
class MockRoutesService implements RoutesService {
  @override
  Future<RouteData> computeRoute({
    required LatLng origin,
    required String destination,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final d = destination.trim().toLowerCase();
    final toKozhikode = d.contains('kozhikode') || d.contains('calicut');
    final toKochi =
        d.contains('kochi') || d.contains('cochin') || d.contains('ernakulam');
    if (!toKozhikode && !toKochi) {
      throw EnRouteException(
        'Sample mode only knows Kochi and Kozhikode as destinations. '
        'Add a Google API key to route anywhere.',
      );
    }

    final base = toKozhikode
        ? _kochiToKozhikode
        : _kochiToKozhikode.reversed.toList(growable: false);
    final proj = nearestOnPolyline(base, origin);
    if (proj.distanceToRouteMeters > 20000) {
      throw EnRouteException(
        'Sample mode only works near the Kochi\u2013Kozhikode road.',
      );
    }

    final points = slicePolyline(
      base,
      proj.alongRouteMeters,
      polylineLengthMeters(base),
    );
    if (points.length < 2) {
      throw EnRouteException("You're already at that destination.");
    }

    // Roads wind more than the sampled shape; scale to a realistic figure.
    final distance = polylineLengthMeters(points) * 1.18;
    return RouteData(
      originLabel: 'Your location',
      destinationLabel: toKozhikode ? 'Kozhikode' : 'Kochi',
      points: points,
      distanceMeters: distance,
      durationSeconds: distance / 12.5, // ~45 km/h average
    );
  }
}

class _Seed {
  const _Seed(
    this.id,
    this.name,
    this.category,
    this.lat,
    this.lng,
    this.address, {
    this.rating,
    this.ratingCount,
    this.openNow,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final double lat;
  final double lng;
  final String address;
  final double? rating;
  final int? ratingCount;
  final bool? openNow;
}

/// Invented places placed near the sample route. Not real businesses.
const List<_Seed> _seeds = [
  // Vegetarian
  _Seed('v1', 'Annapoorna Pure Veg (sample)', PlaceCategory.vegRestaurant,
      10.0285, 76.3140, 'Edappally, Kochi',
      rating: 4.3, ratingCount: 1280, openNow: true),
  _Seed('v2', 'Green Leaf Meals (sample)', PlaceCategory.vegRestaurant,
      10.2290, 76.2010, 'Kodungallur',
      rating: 4.1, ratingCount: 410, openNow: true),
  _Seed('v3', 'Sathvik Bhavan (sample)', PlaceCategory.vegRestaurant,
      10.5810, 76.0330, 'Chavakkad',
      rating: 4.5, ratingCount: 760, openNow: false),
  _Seed('v4', 'Udupi Corner (sample)', PlaceCategory.vegRestaurant,
      10.9700, 76.0400, 'Kottakkal outskirts',
      rating: 3.9, ratingCount: 215, openNow: true),
  _Seed('v5', 'Malabar Sadya House (sample)', PlaceCategory.vegRestaurant,
      11.1680, 75.8700, 'Ramanattukara',
      rating: 4.4, ratingCount: 930, openNow: true),
  // Restaurants
  _Seed('r1', 'Coastal Tadka (sample)', PlaceCategory.restaurant,
      10.1480, 76.2280, 'North Paravur',
      rating: 4.2, ratingCount: 640, openNow: true),
  _Seed('r2', 'Highway Biryani Point (sample)', PlaceCategory.restaurant,
      10.7690, 75.9300, 'Ponnani',
      rating: 4.0, ratingCount: 1500, openNow: true),
  _Seed('r3', 'Backwater Kitchen (sample)', PlaceCategory.restaurant,
      10.3820, 76.1220, 'Kaipamangalam',
      rating: 4.6, ratingCount: 380, openNow: true),
  _Seed('r4', 'Tea & Toast (sample)', PlaceCategory.restaurant,
      11.0510, 75.8650, 'Parappanangadi',
      rating: 3.8, ratingCount: 190, openNow: false),
  // Fuel
  _Seed('f1', 'Highway Fuel Station A (sample)', PlaceCategory.fuel,
      10.0300, 76.3100, 'Edappally Bypass',
      rating: 4.0, ratingCount: 220, openNow: true),
  _Seed('f2', 'Highway Fuel Station B (sample)', PlaceCategory.fuel,
      10.2275, 76.1960, 'Kodungallur',
      rating: 3.7, ratingCount: 140, openNow: true),
  _Seed('f3', 'Highway Fuel Station C (sample)', PlaceCategory.fuel,
      10.5790, 76.0225, 'Chavakkad',
      rating: 4.2, ratingCount: 180, openNow: true),
  _Seed('f4', 'Highway Fuel Station D (sample)', PlaceCategory.fuel,
      10.8460, 76.0450, 'Kuttippuram',
      rating: 3.9, ratingCount: 95, openNow: true),
  _Seed('f5', 'Highway Fuel Station E (sample)', PlaceCategory.fuel,
      11.1710, 75.8670, 'Ramanattukara',
      rating: 4.1, ratingCount: 260, openNow: true),
  // ATMs
  _Seed('a1', 'Bank ATM Kiosk 1 (sample)', PlaceCategory.atm,
      10.1465, 76.2235, 'North Paravur',
      openNow: true),
  _Seed('a2', 'Bank ATM Kiosk 2 (sample)', PlaceCategory.atm,
      10.5775, 76.0200, 'Chavakkad',
      openNow: true),
  _Seed('a3', 'Bank ATM Kiosk 3 (sample)', PlaceCategory.atm,
      10.7660, 75.9240, 'Ponnani',
      openNow: true),
  _Seed('a4', 'Bank ATM Kiosk 4 (sample)', PlaceCategory.atm,
      11.0520, 75.8610, 'Parappanangadi',
      openNow: true),
  // Hospitals
  _Seed('h1', 'Community Hospital (sample)', PlaceCategory.hospital,
      10.2180, 76.2050, 'Kodungallur',
      rating: 4.0, ratingCount: 520, openNow: true),
  _Seed('h2', 'Coastal Medical Centre (sample)', PlaceCategory.hospital,
      10.5900, 76.0400, 'Chavakkad',
      rating: 3.8, ratingCount: 310, openNow: true),
  _Seed('h3', 'District Care Hospital (sample)', PlaceCategory.hospital,
      11.2400, 75.7900, 'Kozhikode',
      rating: 4.3, ratingCount: 1900, openNow: true),
  // Stores
  _Seed('s1', 'Wayside Mart (sample)', PlaceCategory.store,
      10.0270, 76.3135, 'Edappally',
      rating: 4.0, ratingCount: 120, openNow: true),
  _Seed('s2', 'Daily Needs Store (sample)', PlaceCategory.store,
      10.7680, 75.9260, 'Ponnani',
      rating: 3.9, ratingCount: 85, openNow: true),
  _Seed('s3', 'Highway Convenience (sample)', PlaceCategory.store,
      11.0015, 76.0050, 'Kottakkal',
      rating: 4.1, ratingCount: 70, openNow: false),
];

/// Computes detours geometrically against the route, with the same output
/// shape the Google implementation produces.
class MockPlacesService implements PlacesService {
  /// Road distance is longer than the straight line to the route; this is a
  /// rough factor for a detour that leaves the route and comes back.
  static const double _roadFactor = 1.4;

  /// Average speed on side roads (~30 km/h) in m/s.
  static const double _sideRoadSpeed = 8.3;

  @override
  Future<List<Place>> searchAhead({
    required RouteData route,
    required LatLng from,
    required double fromAlongMeters,
    required double toAlongMeters,
    required PlaceCategory category,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final results = <Place>[];
    for (final seed in _seeds) {
      final matches = seed.category == category ||
          (category == PlaceCategory.restaurant &&
              seed.category == PlaceCategory.vegRestaurant);
      if (!matches) continue;

      final location = LatLng(seed.lat, seed.lng);
      final proj = nearestOnPolyline(route.points, location);

      // Only keep places close to the road, inside the searched stretch.
      if (proj.distanceToRouteMeters > 5000) continue;
      if (proj.alongRouteMeters < fromAlongMeters - 150) continue;
      if (proj.alongRouteMeters > toAlongMeters) continue;

      final extraMeters =
          2 * proj.distanceToRouteMeters * _roadFactor + 100; // + turn overhead
      final extraSeconds = extraMeters / _sideRoadSpeed + 30;

      results.add(Place(
        id: seed.id,
        name: seed.name,
        category: seed.category,
        location: location,
        address: seed.address,
        detourMeters: extraMeters,
        detourSeconds: extraSeconds,
        alongRouteMeters: proj.alongRouteMeters,
        rating: seed.rating,
        ratingCount: seed.ratingCount,
        openNow: seed.openNow,
      ));
    }
    return results;
  }
}
