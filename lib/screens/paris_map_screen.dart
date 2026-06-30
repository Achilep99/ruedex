import 'package:flutter/material.dart';

import '../models/street_database.dart';
import '../services/discovery_store.dart';
import '../services/online_game_service.dart';
import '../widgets/paris_street_map.dart';

class ParisMapScreen extends StatefulWidget {
  const ParisMapScreen({
    required this.database,
    required this.discoveryStore,
    required this.onlineGameService,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;
  final OnlineGameService onlineGameService;

  @override
  State<ParisMapScreen> createState() => _ParisMapScreenState();
}

class _ParisMapScreenState extends State<ParisMapScreen> {
  Set<String> _discoveredIds = const {};
  Map<String, String> _onlineOwnership = const {};
  String? _onlineStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await widget.discoveryStore.loadDiscoveredIds();
    var ownership = const <String, String>{};
    String? status;
    if (widget.onlineGameService.isConfigured) {
      try {
        ownership = await widget.onlineGameService.loadStreetOwnership();
        status = 'Saison en ligne';
      } catch (error) {
        status = 'Carte locale · serveur inaccessible';
      }
    } else {
      status = 'Carte locale';
    }
    if (mounted) {
      setState(() {
        _discoveredIds = ids;
        _onlineOwnership = ownership;
        _onlineStatus = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _onlineOwnership.length;
    final localCount = _discoveredIds.length;
    final total = widget.database.streets.length;
    final displayedCount = onlineCount == 0 ? localCount : onlineCount;

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
                  '$displayedCount / $total rues',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                Text(_onlineStatus ?? 'Chargement…'),
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
          teamOwnership: _onlineOwnership,
          teamColorResolver: widget.onlineGameService.colorForTeam,
        ),
      ),
    );
  }
}
