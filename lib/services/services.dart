import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// Thrown for problems the user can understand (bad input, no route, API error).
class EnRouteException implements Exception {
  EnRouteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Where the user is right now.
abstract class LocationService {
  /// One-off fix. Throws [EnRouteException] with a readable message if
  /// location is off or permission is missing.
  Future<LatLng> currentPosition();

  /// Updates as the user moves.
  Stream<LatLng> positionUpdates();
}

/// Computes a drivable route from the user's position to a free-text place.
abstract class RoutesService {
  Future<RouteData> computeRoute({
    required LatLng origin,
    required String destination,
  });
}

/// Finds places on the stretch of [route] ahead of the user and reports the
/// detour each one costs.
abstract class PlacesService {
  /// [from] is the user's real position. [fromAlongMeters] and
  /// [toAlongMeters] bound the part of the route polyline to search, measured
  /// from the polyline's start.
  Future<List<Place>> searchAhead({
    required RouteData route,
    required LatLng from,
    required double fromAlongMeters,
    required double toAlongMeters,
    required PlaceCategory category,
  });
}
