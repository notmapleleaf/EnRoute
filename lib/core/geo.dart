import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const double _earthRadiusM = 6371000;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance between two points, in metres.
double haversineMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(h.toDouble()));
}

/// Total length of a polyline, in metres.
double polylineLengthMeters(List<LatLng> line) {
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += haversineMeters(line[i - 1], line[i]);
  }
  return total;
}

/// Result of projecting a point onto a polyline.
class RouteProjection {
  const RouteProjection({
    required this.distanceToRouteMeters,
    required this.alongRouteMeters,
    required this.segmentIndex,
    required this.point,
  });

  /// Shortest (approximate) distance from the point to the polyline.
  final double distanceToRouteMeters;

  /// Distance travelled along the polyline from its start to the projected point.
  final double alongRouteMeters;

  /// Index of the segment (line[i] -> line[i+1]) the point projects onto.
  final int segmentIndex;

  /// The closest point on the polyline.
  final LatLng point;
}

/// Finds the closest point on [line] to [p].
///
/// Uses a local flat-earth approximation per segment, which is accurate to
/// well under a metre for the segment lengths a road polyline has.
RouteProjection nearestOnPolyline(List<LatLng> line, LatLng p) {
  if (line.length < 2) {
    throw ArgumentError('Polyline needs at least 2 points');
  }
  final cosLat = math.cos(_rad(p.latitude));
  const mPerDegLat = 110540.0;
  const mPerDegLng = 111320.0;

  var bestDist = double.infinity;
  var bestAlong = 0.0;
  var bestIndex = 0;
  var bestT = 0.0;
  var cumulative = 0.0;

  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i];
    final b = line[i + 1];
    final segLen = haversineMeters(a, b);

    // Segment endpoints in metres, with p at the origin.
    final ax = (a.longitude - p.longitude) * mPerDegLng * cosLat;
    final ay = (a.latitude - p.latitude) * mPerDegLat;
    final bx = (b.longitude - p.longitude) * mPerDegLng * cosLat;
    final by = (b.latitude - p.latitude) * mPerDegLat;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    var t = lenSq == 0 ? 0.0 : -(ax * dx + ay * dy) / lenSq;
    t = t.clamp(0.0, 1.0);

    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final dist = math.sqrt(cx * cx + cy * cy);

    if (dist < bestDist) {
      bestDist = dist;
      bestAlong = cumulative + t * segLen;
      bestIndex = i;
      bestT = t;
    }
    cumulative += segLen;
  }

  final a = line[bestIndex];
  final b = line[bestIndex + 1];
  return RouteProjection(
    distanceToRouteMeters: bestDist,
    alongRouteMeters: bestAlong,
    segmentIndex: bestIndex,
    point: LatLng(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    ),
  );
}

/// The part of [line] between [fromMeters] and [toMeters] measured along it.
///
/// The first and last points are interpolated, so the result starts and ends
/// exactly at those distances. Returns an empty list when the range is empty
/// or lies beyond the end of the line.
List<LatLng> slicePolyline(
  List<LatLng> line,
  double fromMeters,
  double toMeters,
) {
  if (line.length < 2 || toMeters <= fromMeters) return const [];
  final out = <LatLng>[];
  var cumulative = 0.0;

  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i];
    final b = line[i + 1];
    final segLen = haversineMeters(a, b);
    final segStart = cumulative;
    final segEnd = cumulative + segLen;
    cumulative = segEnd;

    if (segEnd < fromMeters) continue;
    if (segStart > toMeters) break;

    LatLng at(double meters) {
      if (segLen == 0) return a;
      final t = ((meters - segStart) / segLen).clamp(0.0, 1.0);
      return LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
    }

    if (out.isEmpty) out.add(at(fromMeters));
    out.add(segEnd <= toMeters ? b : at(toMeters));
  }
  return out.length < 2 ? const [] : out;
}

/// Compass bearing from [a] to [b], in degrees clockwise from north (0-360).
double bearingDegrees(LatLng a, LatLng b) {
  final p1 = _rad(a.latitude);
  final p2 = _rad(b.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final y = math.sin(dLng) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// The point [meters] away from [from] when travelling along [bearingDeg].
LatLng destinationPoint(LatLng from, double bearingDeg, double meters) {
  final d = meters / _earthRadiusM;
  final br = _rad(bearingDeg);
  final p1 = _rad(from.latitude);
  final l1 = _rad(from.longitude);
  final p2 = math.asin(
    math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(br),
  );
  final l2 = l1 +
      math.atan2(
        math.sin(br) * math.sin(d) * math.cos(p1),
        math.cos(d) - math.sin(p1) * math.sin(p2),
      );
  return LatLng(p2 * 180 / math.pi, ((l2 * 180 / math.pi) + 540) % 360 - 180);
}

/// Decodes a Google encoded polyline (precision 5).
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Encodes points as a Google encoded polyline (precision 5).
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;

  void writeValue(int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e5).round();
    final lng = (p.longitude * 1e5).round();
    writeValue(lat - prevLat);
    writeValue(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}
