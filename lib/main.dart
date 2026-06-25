import 'package:flutter/material.dart';

import 'models/street_entry.dart';
import 'screens/home_screen.dart';
import 'services/discovery_store.dart';
import 'services/street_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = StreetRepository();
  final streets = await repository.loadStreets();
  final discoveryStore = DiscoveryStore();

  runApp(
    RueDexApp(
      streets: streets,
      discoveryStore: discoveryStore,
    ),
  );
}

class RueDexApp extends StatelessWidget {
  const RueDexApp({
    required this.streets,
    required this.discoveryStore,
    super.key,
  });

  final List<StreetEntry> streets;
  final DiscoveryStore discoveryStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RueDex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C54D6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF11131A),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: HomeScreen(
        streets: streets,
        discoveryStore: discoveryStore,
      ),
    );
  }
}
