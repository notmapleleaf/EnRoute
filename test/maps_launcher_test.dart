import 'package:enroute/models/models.dart';
import 'package:enroute/services/maps_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('directions URL goes from here, via the stop, to the destination', () {
    const route = RouteData(
      originLabel: 'Your location',
      destinationLabel: 'Kozhikode',
      points: [LatLng(10.5, 76.0), LatLng(11.25, 75.78)],
      distanceMeters: 1000,
      durationSeconds: 100,
    );
    const stop = Place(
      id: 'p',
      name: 'Stop',
      category: PlaceCategory.fuel,
      location: LatLng(10.8, 75.9),
      address: '',
      detourMeters: 0,
      detourSeconds: 0,
      alongRouteMeters: 0,
    );

    final uri = MapsLauncher.directionsUri(route, stop);
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['destination'], '11.25,75.78');
    expect(uri.queryParameters['waypoints'], '10.8,75.9');
    // No origin: Google Maps then starts from the device's location.
    expect(uri.queryParameters.containsKey('origin'), isFalse);
  });
}
