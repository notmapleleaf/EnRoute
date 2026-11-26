import 'package:latlong2/latlong.dart';

/// A kind of place the user can search for along a route.
enum PlaceCategory {
  vegRestaurant('Vegetarian', 'vegetarian restaurant'),
  restaurant('Restaurants', 'restaurant'),
  fuel('Fuel', 'petrol pump'),
  atm('ATMs', 'ATM'),
  hospital('Hospitals', 'hospital'),
  store('Stores', 'convenience store');

  const PlaceCategory(this.label, this.query);

  /// Chip label shown in the UI.
  final String label;

  /// Text query sent to the Places API.
  final String query;
}

enum SortMode {
  nearest('Nearest'),
  detourTime('Least detour'),
  rating('Top rated');

  const SortMode(this.label);
  final String label;
}

/// A drivable route from where the user was when it was computed to the
/// destination.
class RouteData {
  const RouteData({
    required this.originLabel,
    required this.destinationLabel,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String originLabel;
  final String destinationLabel;
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  LatLng get origin => points.first;
  LatLng get destination => points.last;
}

/// A place found along a route, with the cost of stopping there.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.address,
    required this.detourMeters,
    required this.detourSeconds,
    required this.alongRouteMeters,
    this.rating,
    this.ratingCount,
    this.openNow,
    this.photoName,
    this.photoAuthor,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final LatLng location;
  final String address;

  /// Google photo resource name ("places/.../photos/..."), if the place has one.
  final String? photoName;

  /// Credit line Google requires next to the photo.
  final String? photoAuthor;

  /// Extra driving distance versus staying on the route.
  final double detourMeters;

  /// Extra driving time versus staying on the route.
  final double detourSeconds;

  /// Where the stop sits along the route polyline, measured from the
  /// polyline's start. Subtract the user's own position along the route to
  /// get "how far ahead".
  final double alongRouteMeters;

  final double? rating;
  final int? ratingCount;
  final bool? openNow;
}
