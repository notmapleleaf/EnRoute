import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'services.dart';

/// Real GPS via the geolocator package.
///
/// Needs location permissions declared in AndroidManifest.xml / Info.plist
/// (see README).
class GeolocatorLocationService implements LocationService {
  @override
  Future<LatLng> currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw EnRouteException('Location is turned off. Turn on GPS and retry.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw EnRouteException(
        'EnRoute needs location permission to find stops near you.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw EnRouteException(
        'Location permission is blocked. Allow it in the app settings, then retry.',
      );
    }

    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } on TimeoutException {
      throw EnRouteException(
        'Could not get a GPS fix. Try again with a clear view of the sky.',
      );
    }
  }

  @override
  Stream<LatLng> positionUpdates() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50, // metres between updates
      ),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }
}
