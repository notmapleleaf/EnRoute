import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/enroute_controller.dart';
import 'map_view.dart';
import 'place_widgets.dart';
import 'top_panel.dart';

/// Full-screen map with everything else floating on top of it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EnRouteController>();
    final selected = c.selected;

    return Scaffold(
      // Keep the map still while the keyboard is open.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: EnRouteMap()),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: TopPanel()),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                    child: FloatingActionButton.small(
                      heroTag: 'recenter',
                      tooltip: 'Recenter',
                      onPressed: c.recenter,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                  // Only appears once a stop is tapped, so it never covers
                  // the map otherwise.
                  if (selected != null)
                    SizedBox(
                      width: double.infinity,
                      child: SelectedPlaceBar(
                        place: selected,
                        ahead: c.distanceAhead(selected),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
