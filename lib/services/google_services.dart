import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../models/models.dart';
import 'services.dart';

// NOTE: The route lookup has been seen working against the live API. The
// Places search below has NOT been run live yet: check the response shapes on
// the first real call.

/// "123s" -> 123.0
double _parseDurationSeconds(Object? value) {
  if (value is String && value.endsWith('s')) {
    return double.tryParse(value.substring(0, value.length - 1)) ?? 0;
  }
  return 0;
}

Never _fail(http.Response res, String what) {
  var detail = '';
  try {
    final body = jsonDecode(res.body);
    detail = (body['error']?['message'] ?? '').toString();
  } catch (_) {}
  throw EnRouteException(
    '$what failed (${res.statusCode})${detail.isEmpty ? '' : ': $detail'}',
  );
}

/// Routes API: computeRoutes -> polyline, distance, duration.
class GoogleRoutesService implements RoutesService {
  GoogleRoutesService(this.apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<RouteData> computeRoute({
    required LatLng origin,
    required String destination,
  }) async {
    final res = await _client.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
      },
      body: jsonEncode({
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
          },
        },
        'destination': {'address': destination},
        'travelMode': 'DRIVE',
        'regionCode': 'IN',
      }),
    );
    if (res.statusCode != 200) _fail(res, 'Route lookup');

    final routes = (jsonDecode(res.body)['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw EnRouteException('No driving route found to that destination.');
    }
    final r = routes.first as Map<String, dynamic>;
    final points = decodePolyline(r['polyline']['encodedPolyline'] as String);
    if (points.length < 2) {
      throw EnRouteException("You're already at that destination.");
    }
    return RouteData(
      originLabel: 'Your location',
      destinationLabel: destination,
      points: points,
      distanceMeters: (r['distanceMeters'] as num).toDouble(),
      durationSeconds: _parseDurationSeconds(r['duration']),
    );
  }
}

/// Places API (New): Text Search with searchAlongRouteParameters, limited to
/// the stretch of road just ahead of the user.
///
/// With routingParameters.origin set, Google returns a routing summary per
/// place with two legs: user -> place and place -> end of the searched
/// stretch. Detour = those two legs minus the plain drive over the stretch.
class GooglePlacesService implements PlacesService {
  GooglePlacesService(this.apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<List<Place>> searchAhead({
    required RouteData route,
    required LatLng from,
    required double fromAlongMeters,
    required double toAlongMeters,
    required PlaceCategory category,
  }) async {
    final window = slicePolyline(route.points, fromAlongMeters, toAlongMeters);
    if (window.length < 2) return const [];

    // What driving the stretch costs with no stop. Duration is scaled from
    // the whole route's duration by distance (an estimate).
    final windowMeters = polylineLengthMeters(window);
    final routeMeters = polylineLengthMeters(route.points);
    final baselineSeconds = routeMeters == 0
        ? 0.0
        : route.durationSeconds * windowMeters / routeMeters;

    final res = await _client.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchText'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,'
            'places.location,places.rating,places.userRatingCount,'
            'places.currentOpeningHours.openNow,places.photos,routingSummaries',
      },
      body: jsonEncode({
        'textQuery': category.query,
        'maxResultCount': 20,
        'searchAlongRouteParameters': {
          'polyline': {'encodedPolyline': encodePolyline(window)},
        },
        // Measure detours from the start of the searched band, on the route,
        // so a band further ahead isn't charged for the road before it.
        'routingParameters': {
          'origin': {
            'latitude': window.first.latitude,
            'longitude': window.first.longitude,
          },
        },
      }),
    );
    if (res.statusCode != 200) _fail(res, 'Place search');

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rawPlaces = (body['places'] as List?) ?? const [];
    final summaries = (body['routingSummaries'] as List?) ?? const [];

    final out = <Place>[];
    final seen = <String>{};
    for (var i = 0; i < rawPlaces.length; i++) {
      final p = rawPlaces[i] as Map<String, dynamic>;
      final id = p['id'] as String;
      if (!seen.add(id)) continue; // drop duplicates

      var detourM = 0.0;
      var detourS = 0.0;
      if (i < summaries.length) {
        final legs = (summaries[i]['legs'] as List?) ?? const [];
        var totalM = 0.0;
        var totalS = 0.0;
        for (final leg in legs) {
          totalM += ((leg['distanceMeters'] ?? 0) as num).toDouble();
          totalS += _parseDurationSeconds(leg['duration']);
        }
        detourM =
            (totalM - windowMeters).clamp(0.0, double.infinity).toDouble();
        detourS =
            (totalS - baselineSeconds).clamp(0.0, double.infinity).toDouble();
      }

      // First photo only; its image is fetched later, when the stop is tapped.
      String? photoName;
      String? photoAuthor;
      final photos = p['photos'];
      if (photos is List && photos.isNotEmpty) {
        final first = photos.first as Map<String, dynamic>;
        photoName = first['name'] as String?;
        final authors = first['authorAttributions'];
        if (authors is List && authors.isNotEmpty) {
          photoAuthor = (authors.first as Map<String, dynamic>)['displayName']
              as String?;
        }
      }

      final loc = p['location'] as Map<String, dynamic>;
      final location = LatLng(
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );
      out.add(Place(
        id: id,
        name: (p['displayName']?['text'] ?? 'Unnamed place') as String,
        category: category,
        location: location,
        address: (p['formattedAddress'] ?? '') as String,
        detourMeters: detourM,
        detourSeconds: detourS,
        alongRouteMeters:
            nearestOnPolyline(route.points, location).alongRouteMeters,
        rating: (p['rating'] as num?)?.toDouble(),
        ratingCount: (p['userRatingCount'] as num?)?.toInt(),
        openNow: p['currentOpeningHours']?['openNow'] as bool?,
        photoName: photoName,
        photoAuthor: photoAuthor,
      ));
    }
    return out;
  }
}
