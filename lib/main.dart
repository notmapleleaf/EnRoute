import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/config.dart';
import 'services/geolocator_location.dart';
import 'services/google_services.dart';
import 'services/mock_services.dart';
import 'services/services.dart';
import 'state/enroute_controller.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const EnRouteApp());
}

class EnRouteApp extends StatelessWidget {
  const EnRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // One switch decides whether we talk to Google and the real GPS, or use
    // sample data and a pretend position.
    final RoutesService routes = AppConfig.useMock
        ? MockRoutesService()
        : GoogleRoutesService(AppConfig.googleApiKey);
    final PlacesService places = AppConfig.useMock
        ? MockPlacesService()
        : GooglePlacesService(AppConfig.googleApiKey);
    final LocationService location = AppConfig.useMock
        ? MockLocationService()
        : GeolocatorLocationService();

    return ChangeNotifierProvider(
      create: (_) => EnRouteController(
        routes: routes,
        places: places,
        location: location,
      )..init(),
      child: MaterialApp(
        title: 'EnRoute',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0B7A75),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0B7A75),
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
