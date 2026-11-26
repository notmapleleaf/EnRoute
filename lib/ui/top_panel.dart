import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../models/models.dart';
import '../services/config.dart';
import '../state/enroute_controller.dart';

/// Everything floating at the top of the map: destination box, category
/// chips, search-range/sort pills and any error message.
class TopPanel extends StatefulWidget {
  const TopPanel({super.key});

  @override
  State<TopPanel> createState() => _TopPanelState();
}

class _TopPanelState extends State<TopPanel> {
  final _destination = TextEditingController();

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<EnRouteController>().setDestination(_destination.text);
  }

  void _endTrip() {
    _destination.clear();
    context.read<EnRouteController>().clearRoute();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EnRouteController>();
    final scheme = Theme.of(context).colorScheme;
    final busy = c.locating || c.loadingRoute || c.loadingPlaces;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            elevation: 4,
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: c.route == null ? _searchRow(c) : _tripRow(c),
            ),
          ),
          SizedBox(
            height: 5,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.only(top: 2, left: 8, right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: const LinearProgressIndicator(minHeight: 3),
                    ),
                  )
                : null,
          ),
          if (c.route != null) ...[
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final cat in PlaceCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(cat.label),
                        selected: c.category == cat,
                        showCheckmark: false,
                        elevation: 2,
                        backgroundColor: scheme.surface,
                        selectedColor: scheme.primaryContainer,
                        onSelected: (_) => c.selectCategory(cat),
                      ),
                    ),
                ],
              ),
            ),
            if (c.category != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Pill(
                      icon: Icons.straighten,
                      label: c.canLookNearer
                          ? '${(c.lookFromMeters / 1000).round()}–'
                              '${(c.lookAheadMeters / 1000).round()} km ahead'
                          : 'Next ${(c.lookAheadMeters / 1000).round()} km',
                    ),
                    if (c.canLookNearer)
                      _Pill(
                        icon: Icons.remove,
                        label: 'Nearer',
                        onTap: c.lookNearer,
                      ),
                    if (c.canLookFurther)
                      _Pill(
                        icon: Icons.add,
                        label: 'Look further',
                        onTap: c.lookFurther,
                      ),
                    PopupMenuButton<SortMode>(
                      tooltip: 'Sort',
                      onSelected: c.setSort,
                      itemBuilder: (_) => [
                        for (final m in SortMode.values)
                          PopupMenuItem(value: m, child: Text(m.label)),
                      ],
                      child: _Pill(icon: Icons.sort, label: c.sort.label),
                    ),
                  ],
                ),
              ),
          ],
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                elevation: 3,
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.error!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (c.locationFailed) {
                            c.init();
                          } else {
                            c.clearError();
                          }
                        },
                        child: Text(c.locationFailed ? 'Retry' : 'Dismiss'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (AppConfig.useMock)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: _Pill(
                icon: Icons.science_outlined,
                label: 'Sample data · pretend position near Chavakkad',
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchRow(EnRouteController c) {
    return Row(
      children: [
        const Icon(Icons.search),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _destination,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: c.locating ? 'Finding your location…' : 'Where to?',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Start',
          onPressed: c.loadingRoute || c.locating ? null : _submit,
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }

  Widget _tripRow(EnRouteController c) {
    return Row(
      children: [
        const Icon(Icons.flag, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.destination ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatDistance(c.remainingMeters)} left · '
                  '${formatDuration(c.remainingSeconds)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'End trip',
          onPressed: _endTrip,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 4),
              ],
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
