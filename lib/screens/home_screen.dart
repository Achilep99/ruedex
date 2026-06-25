import 'package:flutter/material.dart';

import '../models/street_entry.dart';
import '../services/discovery_store.dart';
import 'pokedex_screen.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.streets,
    required this.discoveryStore,
    super.key,
  });

  final List<StreetEntry> streets;
  final DiscoveryStore discoveryStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Set<String> _discoveredIds = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadDiscoveries();
  }

  Future<void> _reloadDiscoveries() async {
    final ids = await widget.discoveryStore.loadDiscoveredIds();
    if (!mounted) return;
    setState(() {
      _discoveredIds = ids;
      _loading = false;
    });
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          streets: widget.streets,
          discoveryStore: widget.discoveryStore,
        ),
      ),
    );
    await _reloadDiscoveries();
  }

  Future<void> _openPokedex() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PokedexScreen(
          streets: widget.streets,
          discoveryStore: widget.discoveryStore,
        ),
      ),
    );
    await _reloadDiscoveries();
  }

  @override
  Widget build(BuildContext context) {
    final count = _discoveredIds.length;
    final total = widget.streets.length;
    final progress = total == 0 ? 0.0 : count / total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RueDex'),
        actions: [
          IconButton(
            tooltip: 'Pokédex des rues',
            onPressed: _openPokedex,
            icon: const Icon(Icons.collections_bookmark_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Attrape les rues de ta ville.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photographie une plaque, laisse l’OCR lire son nom, puis confirme la découverte.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
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
                        Text(
                          _loading ? 'Chargement…' : '$count / $total rues découvertes',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _loading ? null : progress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Scanner une plaque'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openPokedex,
              icon: const Icon(Icons.grid_view_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Ouvrir le RueDex'),
              ),
            ),
            const SizedBox(height: 28),
            const _DeveloperHint(),
          ],
        ),
      ),
    );
  }
}

class _DeveloperHint extends StatelessWidget {
  const _DeveloperHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le scanner possède un mode développeur : texte OCR simulé, coordonnées GPS manuelles et détail des scores.',
            ),
          ),
        ],
      ),
    );
  }
}
