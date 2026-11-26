import 'package:enroute/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('haversine: Kochi to Kozhikode is roughly 160 km straight-line', () {
    final d = haversineMeters(const LatLng(9.9312, 76.2673),
        const LatLng(11.2588, 75.7804));
    expect(d, inInclusiveRange(150000, 170000));
  });

  test('polyline encode/decode round-trips (Google reference example)', () {
    // From Google's encoded polyline algorithm documentation.
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final pts = decodePolyline(encoded);
    expect(pts.length, 3);
    expect(pts[0].latitude, closeTo(38.5, 1e-5));
    expect(pts[0].longitude, closeTo(-120.2, 1e-5));
    expect(pts[2].latitude, closeTo(43.252, 1e-5));
    expect(pts[2].longitude, closeTo(-126.453, 1e-5));
    expect(encodePolyline(pts), encoded);
  });

  test('nearestOnPolyline measures distance and position along the line', () {
    const line = [LatLng(0, 0), LatLng(0, 1)]; // ~111 km along the equator
    // A point 0.01 deg north of the midpoint (~1.1 km off the line).
    final proj = nearestOnPolyline(line, const LatLng(0.01, 0.5));
    expect(proj.distanceToRouteMeters, inInclusiveRange(1000, 1200));
    expect(proj.alongRouteMeters,
        closeTo(polylineLengthMeters(line) / 2, 500));
    // ...and returns the closest point on the line itself.
    expect(proj.point.latitude, closeTo(0, 1e-6));
    expect(proj.point.longitude, closeTo(0.5, 1e-3));
  });

  test('nearestOnPolyline clamps to segment ends', () {
    const line = [LatLng(0, 0), LatLng(0, 1)];
    final proj = nearestOnPolyline(line, const LatLng(0, -0.5));
    expect(proj.alongRouteMeters, closeTo(0, 1));
    expect(proj.distanceToRouteMeters, inInclusiveRange(50000, 61000));
  });

  group('bearing and destination point', () {
    test('compass bearings', () {
      const o = LatLng(10, 76);
      expect(bearingDegrees(o, const LatLng(11, 76)), closeTo(0, 0.01));
      expect(bearingDegrees(o, const LatLng(10, 77)), closeTo(90, 0.5));
      expect(bearingDegrees(o, const LatLng(9, 76)), closeTo(180, 0.01));
      expect(bearingDegrees(o, const LatLng(10, 75)), closeTo(270, 0.5));
    });

    test('destinationPoint goes the right way and distance', () {
      const o = LatLng(10, 76);
      final east = destinationPoint(o, 90, 5000);
      expect(haversineMeters(o, east), closeTo(5000, 5));
      expect(east.longitude, greaterThan(76));
      expect(east.latitude, closeTo(10, 1e-3));

      final north = destinationPoint(o, 0, 5000);
      expect(north.latitude, greaterThan(10));
      expect(bearingDegrees(o, north), closeTo(0, 0.1));
    });
  });

  group('slicePolyline', () {
    test('cuts a single segment at exact distances', () {
      const line = [LatLng(0, 0), LatLng(0, 1)];
      final s = slicePolyline(line, 10000, 20000);
      expect(s.length, 2);
      expect(polylineLengthMeters(s), closeTo(10000, 1));
    });

    test('keeps vertices that fall inside the range', () {
      // Vertex at ~11.1 km.
      const line = [LatLng(0, 0), LatLng(0, 0.1), LatLng(0, 0.2)];
      final s = slicePolyline(line, 5000, 15000);
      expect(s.length, 3);
      expect(s[1].longitude, closeTo(0.1, 1e-9));
      expect(polylineLengthMeters(s), closeTo(10000, 1));
    });

    test('whole line when range covers it', () {
      const line = [LatLng(0, 0), LatLng(0, 0.1), LatLng(0, 0.2)];
      final s = slicePolyline(line, 0, 1e9);
      expect(s.length, 3);
      expect(polylineLengthMeters(s),
          closeTo(polylineLengthMeters(line), 1));
    });

    test('empty for empty or out-of-range requests', () {
      const line = [LatLng(0, 0), LatLng(0, 0.1)];
      expect(slicePolyline(line, 5000, 5000), isEmpty);
      expect(slicePolyline(line, 9000, 1000), isEmpty);
      expect(slicePolyline(line, 50000, 60000), isEmpty);
    });
  });
}
