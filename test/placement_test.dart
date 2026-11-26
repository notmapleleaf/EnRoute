import 'package:enroute/core/placement.dart';
import 'package:enroute/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

RouteData _route(List<LatLng> pts) => RouteData(
      originLabel: 'a',
      destinationLabel: 'b',
      points: pts,
      distanceMeters: 1000,
      durationSeconds: 100,
    );

Place _place(double lat, double lng) => Place(
      id: 'x',
      name: 'x',
      category: PlaceCategory.fuel,
      location: LatLng(lat, lng),
      address: '',
      detourMeters: 0,
      detourSeconds: 0,
      alongRouteMeters: 0,
    );

void main() {
  group('north-south road', () {
    final route = _route(const [LatLng(10, 76), LatLng(11, 76)]);

    test('place east of the road gets a card on the right', () {
      expect(cardSideFor(route, _place(10.5, 76.01), 0), CardSide.right);
    });

    test('place west of the road gets a card on the left', () {
      expect(cardSideFor(route, _place(10.5, 75.99), 0), CardSide.left);
    });

    test('place right on the road alternates sides', () {
      expect(cardSideFor(route, _place(10.5, 76), 0), CardSide.right);
      expect(cardSideFor(route, _place(10.5, 76), 1), CardSide.left);
    });
  });

  group('map turned to face the direction of travel', () {
    // Driving east along an east-west road: north is on your left.
    final route = _route(const [LatLng(10, 76), LatLng(10, 77)]);

    test('a stop north of an eastbound road is on the left of the screen', () {
      expect(
        cardSideFor(route, _place(10.01, 76.5), 0, headingDeg: 90),
        CardSide.left,
      );
    });

    test('a stop south of an eastbound road is on the right of the screen',
        () {
      expect(
        cardSideFor(route, _place(9.99, 76.5), 0, headingDeg: 90),
        CardSide.right,
      );
    });

    test('driving north, east is still on the right', () {
      final northRoute = _route(const [LatLng(10, 76), LatLng(11, 76)]);
      expect(
        cardSideFor(northRoute, _place(10.5, 76.01), 0, headingDeg: 0),
        CardSide.right,
      );
    });
  });

  group('east-west road', () {
    final route = _route(const [LatLng(10, 76), LatLng(10, 77)]);

    test('place north of the road gets a card above', () {
      expect(cardSideFor(route, _place(10.01, 76.5), 0), CardSide.above);
    });

    test('place south of the road gets a card below', () {
      expect(cardSideFor(route, _place(9.99, 76.5), 0), CardSide.below);
    });
  });
}
