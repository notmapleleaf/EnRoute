import 'dart:math' as math;

import '../models/models.dart';
import 'geo.dart';

/// Which side of its pin a place's floating card is drawn on, as seen on screen.
enum CardSide { left, right, above, below }

/// Chooses a side for [place]'s card so it sits beside the road, not on it.
///
/// [headingDeg] is the direction the map is turned to face (degrees clockwise
/// from north); 0 means north is up. In drive mode the travel direction is up
/// on screen, so a stop on your right gets its card on the right.
///
/// For a road that runs mostly up-down on screen the card goes left or right
/// (towards the side the place is actually on); for a mostly sideways road it
/// goes above or below. Places almost exactly on the road alternate by
/// [index] so neighbouring cards don't stack on one side.
CardSide cardSideFor(
  RouteData route,
  Place place,
  int index, {
  double headingDeg = 0,
}) {
  final proj = nearestOnPolyline(route.points, place.location);
  final a = route.points[proj.segmentIndex];
  final b = route.points[proj.segmentIndex + 1];

  final cosLat = math.cos(place.location.latitude * math.pi / 180);
  // East/north components (in comparable units) of the road direction and of
  // the place's offset from the road.
  final routeE = (b.longitude - a.longitude) * cosLat;
  final routeN = b.latitude - a.latitude;
  final offE = (place.location.longitude - proj.point.longitude) * cosLat;
  final offN = place.location.latitude - proj.point.latitude;

  // Turn them into screen directions for a map facing [headingDeg].
  final h = headingDeg * math.pi / 180;
  final cosH = math.cos(h);
  final sinH = math.sin(h);
  double screenRight(double e, double n) => e * cosH - n * sinH;
  double screenUp(double e, double n) => e * sinH + n * cosH;

  final roadX = screenRight(routeE, routeN);
  final roadY = screenUp(routeE, routeN);
  final offX = screenRight(offE, offN);
  final offY = screenUp(offE, offN);

  const tiny = 1e-6; // ~0.1 m
  if (roadY.abs() >= roadX.abs()) {
    if (offX.abs() < tiny) {
      return index.isEven ? CardSide.right : CardSide.left;
    }
    return offX > 0 ? CardSide.right : CardSide.left;
  }
  if (offY.abs() < tiny) {
    return index.isEven ? CardSide.above : CardSide.below;
  }
  return offY > 0 ? CardSide.above : CardSide.below;
}
