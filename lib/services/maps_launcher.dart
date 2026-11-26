import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// Hands the journey over to Google Maps with the chosen stop as a waypoint.
class MapsLauncher {
  const MapsLauncher._();

  /// Directions from wherever the user is now (no origin given, so Google Maps
  /// uses the device location) via [stop] to the original destination.
  static Uri directionsUri(RouteData route, Place stop) {
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination':
          '${route.destination.latitude},${route.destination.longitude}',
      'waypoints': '${stop.location.latitude},${stop.location.longitude}',
      'travelmode': 'driving',
    });
  }

  static Future<bool> open(RouteData route, Place stop) {
    return launchUrl(
      directionsUri(route, stop),
      mode: LaunchMode.externalApplication,
    );
  }
}
