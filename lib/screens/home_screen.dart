import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/street_database.dart';
import '../services/app_settings_store.dart';
import '../services/discovery_store.dart';
import 'paris_map_screen.dart';
import 'pokedex_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.database,
    required this.discoveryStore,
    required this.settingsStore,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;
  final AppSettingsStore settingsStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Set<String> _discoveredIds = const {};
  bool _developerMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ids = await widget.discoveryStore.loadDiscoveredIds();
    final developerMode = await widget.settingsStore.loadDeveloperMode();
    if (!mounted) return;
    setState(() {
      _discoveredIds = ids;
      _developerMode = developerMode;
      _loading = false;
    });
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          database: widget.database,
          discoveryStore: widget.discoveryStore,
          developerMode: _developerMode,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openPokedex() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PokedexScreen(
          streets: widget.database.streets,
          discoveryStore: widget.discoveryStore,
          developerMode: _developerMode,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ParisMapScreen(
          database: widget.database,
          discoveryStore: widget.discoveryStore,
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    var value = _developerMode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Réglages de test', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mode développeur'),
                subtitle: const Text(
                  'Désactivé, l’application est exactement dans le mode joueur : scan direct, GPS réel et aucun choix manuel.',
                ),
                value: value,
                onChanged: (next) async {
                  value = next;
                  setSheetState(() {});
                  await widget.settingsStore.setDeveloperMode(next);
                  if (mounted) setState(() => _developerMode = next);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _discoveredIds.length;
    final total = widget.database.streets.length;
    final progress = total == 0 ? 0.0 : count / total;

    return Scaffold(
      appBar: AppBar(
        title: AppConfig.developerToolsAvailable
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _showSettings,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('RueDex'),
                ),
              )
            : const Text('RueDex'),
        actions: [
          if (AppConfig.developerToolsAvailable && _developerMode)
            IconButton(
              tooltip: 'Réglages développeur',
              onPressed: _showSettings,
              icon: const Icon(Icons.science),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Paris devient ton terrain de chasse.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cadre une plaque : le scan, le GPS et la validation travaillent automatiquement.',
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.route),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _loading ? 'Chargement…' : '$count / $total rues découvertes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _loading ? null : progress),
                    if (_developerMode) ...[
                      const SizedBox(height: 10),
                      const Text('Mode développeur actif', style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.center_focus_strong),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 17),
                child: Text('Lancer le scanner direct'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Ma carte'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openPokedex,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('RueDex'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Données géographiques : ${widget.database.sourceLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
