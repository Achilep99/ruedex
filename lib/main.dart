import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'models/street_database.dart';
import 'screens/home_screen.dart';
import 'services/app_settings_store.dart';
import 'services/discovery_store.dart';
import 'services/online_game_service.dart';
import 'services/street_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  final database = await StreetRepository().loadDatabase();

  runApp(
    RueDexApp(
      database: database,
      discoveryStore: DiscoveryStore(),
      settingsStore: AppSettingsStore(),
      onlineGameService: OnlineGameService(),
    ),
  );
}

class RueDexApp extends StatelessWidget {
  const RueDexApp({
    required this.database,
    required this.discoveryStore,
    required this.settingsStore,
    required this.onlineGameService,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;
  final AppSettingsStore settingsStore;
  final OnlineGameService onlineGameService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RueDex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6D5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF10131A),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: HomeScreen(
        database: database,
        discoveryStore: discoveryStore,
        settingsStore: settingsStore,
        onlineGameService: onlineGameService,
      ),
    );
  }
}
