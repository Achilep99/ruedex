import 'package:flutter/material.dart';

import '../models/street_database.dart';
import '../services/discovery_store.dart';
import '../widgets/paris_street_map.dart';

class ParisMapScreen extends StatefulWidget {
  const ParisMapScreen({
    required this.database,
    required this.discoveryStore,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;

  @override
  State<ParisMapScreen> createState() => _ParisMapScreenState();
}

class _ParisMapScreenState extends State<ParisMapScreen> {
  Set<String> _discoveredIds = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await widget.discoveryStore.loadDiscoveredIds();
    if (mounted) setState(() {
      => _discoveredIds = ids);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma carte de Paris'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  '${_discoveredIds.length} / ${widget.database.streets.length} rues',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                const Text('Aucun nom affiché'),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: ParisStreetMap(
          streets: widget.database.streets,
          bounds: widget.database.bounds,
          discoveredIds: _discoveredIds,
        ),
      ),
    );
  }
}
