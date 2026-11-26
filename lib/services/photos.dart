import '../models/models.dart';
import 'config.dart';

/// URL of [place]'s photo from the Places API (New), or null when there is no
/// photo (always the case in sample mode).
///
/// Each image load is billed by Google as a photo request, so only call this
/// for a place the user has actually opened.
String? placePhotoUrl(Place place, {int maxWidth = 640}) {
  final name = place.photoName;
  if (name == null || AppConfig.useMock) return null;
  return Uri.https(
    'places.googleapis.com',
    '/v1/$name/media',
    {'maxWidthPx': '$maxWidth', 'key': AppConfig.googleApiKey},
  ).toString();
}
