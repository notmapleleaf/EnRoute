import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/placement.dart';
import '../models/models.dart';
import '../services/photos.dart';
import '../state/enroute_controller.dart';

/// A place on the map: a red map pin whose tip sits exactly on the place, with
/// a small floating card beside it. The marker box is centred on the place and
/// big enough to hold the card on any side.
class PlaceMarker extends StatelessWidget {
  const PlaceMarker({
    super.key,
    required this.place,
    required this.ahead,
    required this.side,
    required this.selected,
    required this.onTap,
  });

  /// Height of a normal pin.
  static const double pinSize = 36;

  /// Space between the pin and the card.
  static const double gap = 12;

  /// Horizontal space reserved either side of the pin before a side card starts.
  static const double sideGap = 22;

  /// Size of the marker box to give flutter_map's Marker.
  static const double boxWidth = 2 * (PlaceCard.width + sideGap);
  static const double boxHeight = 2 * (PlaceCard.height + gap + pinSize);

  final Place place;
  final double ahead;
  final CardSide side;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 46.0 : pinSize;

    // Pins are drawn centred, so lift them by half their height to put the
    // tip (not the middle) on the real location.
    final pin = Transform.translate(
      offset: Offset(0, -(size + 5) / 2),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // White outline, then the red pin on top.
            Icon(Icons.location_on, size: size + 5, color: Colors.white),
            Icon(
              Icons.location_on,
              size: size,
              color: selected
                  ? const Color(0xFFB71C1C)
                  : const Color(0xFFE53935),
            ),
          ],
        ),
      ),
    );

    final card = SizedBox(
      width: PlaceCard.width,
      height: PlaceCard.height,
      child: PlaceCard(
        place: place,
        ahead: ahead,
        selected: selected,
        onTap: onTap,
      ),
    );

    // Bottom padding of one pin height keeps side cards level with the pin's
    // body rather than its tip.
    final Widget placedCard = switch (side) {
      CardSide.left => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: pinSize),
            child: card,
          ),
        ),
      CardSide.right => Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: pinSize),
            child: card,
          ),
        ),
      CardSide.above => Align(alignment: Alignment.topCenter, child: card),
      CardSide.below => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: pinSize),
            child: card,
          ),
        ),
    };

    return Stack(
      children: [
        placedCard,
        Center(child: pin),
      ],
    );
  }
}

/// The small floating preview shown beside a stop.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.ahead,
    required this.selected,
    required this.onTap,
  });

  static const double width = 142;
  static const double height = 66;

  final Place place;
  final double ahead;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (place.rating != null) '★ ${place.rating!.toStringAsFixed(1)}',
      if (place.openNow != null) place.openNow! ? 'Open' : 'Closed',
    ];
    const small = TextStyle(fontSize: 11, height: 1.2);

    return Material(
      elevation: selected ? 8 : 4,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.deepOrange : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              Text(
                meta.isEmpty ? place.address : meta.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
              Text(
                '+${formatDuration(place.detourSeconds)} · '
                '${formatDistance(math.max(0.0, ahead))} ahead',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown only while a stop is selected.
class SelectedPlaceBar extends StatelessWidget {
  const SelectedPlaceBar({super.key, required this.place, required this.ahead});

  final Place place;
  final double ahead;

  @override
  Widget build(BuildContext context) {
    final c = context.read<EnRouteController>();
    final theme = Theme.of(context);
    final open = place.openNow;
    final photoUrl = placePhotoUrl(place);

    return Material(
      elevation: 12,
      color: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photoUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 130,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          // Hide the photo area if it can't load.
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported_outlined),
                          ),
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                        ),
                        if (place.photoAuthor != null)
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                'Photo: ${place.photoAuthor}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => c.select(null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(place.address, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (place.rating != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.star, size: 16),
                    label: Text(
                      place.rating!.toStringAsFixed(1) +
                          (place.ratingCount != null
                              ? ' (${place.ratingCount})'
                              : ''),
                    ),
                  ),
                if (open != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(open ? 'Open now' : 'Closed now'),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.alt_route, size: 16),
                  label: Text(
                    '+${formatDuration(place.detourSeconds)} detour · '
                    '${formatDistance(math.max(0.0, ahead))} ahead',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: c.addSelectedToRoute,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Add to Route in Google Maps'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
