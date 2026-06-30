import 'dart:async';

import 'package:flutter/material.dart';

import '../models/street_database.dart';
import '../services/discovery_store.dart';
import '../services/online_game_service.dart';
import '../widgets/paris_street_map.dart';

enum ParisMapMode { personal, conquest }

class ParisMapScreen extends StatefulWidget {
  const ParisMapScreen({
    required this.database,
    required this.discoveryStore,
    required this.onlineGameService,
    required this.mode,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;
  final OnlineGameService onlineGameService;
  final ParisMapMode mode;

  @override
  State<ParisMapScreen> createState() => _ParisMapScreenState();
}

class _ParisMapScreenState extends State<ParisMapScreen> {
  StreamSubscription<Set<String>>? _personalSubscription;
  StreamSubscription<Map<String, String>>? _ownershipSubscription;
  Set<String> _discoveredIds = const {};
  Map<String, String> _onlineOwnership = const {};
  String? _status;

  bool get _isConquest => widget.mode == ParisMapMode.conquest;

  @override
  void initState() {
    super.initState();
    _loadAndWatch();
  }

  @override
  void didUpdateWidget(covariant ParisMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _loadAndWatch();
    }
  }

  @override
  void dispose() {
    _personalSubscription?.cancel();
    _ownershipSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAndWatch() async {
    await _personalSubscription?.cancel();
    await _ownershipSubscription?.cancel();
    _personalSubscription = null;
    _ownershipSubscription = null;

    if (_isConquest) {
      await _loadConquest();
      _watchConquest();
    } else {
      await _loadPersonal();
      _watchPersonal();
    }
  }

  Future<void> _loadPersonal() async {
    final localIds = await widget.discoveryStore.loadDiscoveredIds();
    Set<String> ids = localIds;
    String status = 'Carte personnelle locale';
    if (widget.onlineGameService.isConfigured &&
        widget.onlineGameService.currentUser != null) {
      try {
        final onlineIds = await widget.onlineGameService.loadPersonalDiscoveries();
        ids = {...localIds, ...onlineIds};
        status = 'Carte personnelle synchronisée';
      } catch (error) {
        status = 'Carte personnelle locale · serveur inaccessible';
      }
    }
    if (!mounted) return;
    setState(() {
      _discoveredIds = ids;
      _onlineOwnership = const {};
      _status = status;
    });
  }

  void _watchPersonal() {
    if (!widget.onlineGameService.isConfigured ||
        widget.onlineGameService.currentUser == null) {
      return;
    }
    _personalSubscription = widget.onlineGameService.watchPersonalDiscoveries().listen(
      (ids) async {
        final localIds = await widget.discoveryStore.loadDiscoveredIds();
        if (!mounted) return;
        setState(() {
          _discoveredIds = {...localIds, ...ids};
          _status = 'Carte personnelle synchronisée en direct';
        });
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _status = 'Synchronisation personnelle coupée');
        }
      },
    );
  }

  Future<void> _loadConquest() async {
    Map<String, String> ownership = const {};
    String status = 'Carte de conquête locale';
    if (widget.onlineGameService.isConfigured) {
      try {
        ownership = await widget.onlineGameService.loadStreetOwnership();
        status = 'Conquête synchronisée';
      } catch (error) {
        status = 'Conquête inaccessible : $error';
      }
    }
    if (!mounted) return;
    setState(() {
      _discoveredIds = const {};
      _onlineOwnership = ownership;
      _status = status;
    });
  }

  void _watchConquest() {
    if (!widget.onlineGameService.isConfigured) return;
    _ownershipSubscription = widget.onlineGameService.watchStreetOwnership().listen(
      (ownership) {
        if (!mounted) return;
        setState(() {
          _onlineOwnership = ownership;
          _status = 'Conquête synchronisée en direct';
        });
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _status = 'Synchronisation conquête coupée');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.database.streets.length;
    final displayedCount = _isConquest ? _onlineOwnership.length : _discoveredIds.length;
    final title = _isConquest ? 'Carte de conquête' : 'Ma carte de Paris';
    final subtitle = _isConquest
        ? 'Couleurs des équipes · aucun nom de rue'
        : 'Ta collection · couleurs de rareté · aucun nom de rue';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$displayedCount / $total rues',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Spacer(),
                    Text(_status ?? 'Chargement…'),
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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
          discoveredIds: _isConquest ? const {} : _discoveredIds,
          teamOwnership: _isConquest ? _onlineOwnership : const {},
          teamColorResolver: widget.onlineGameService.colorForTeam,
          legendMode: _isConquest ? MapLegendMode.teams : MapLegendMode.rarity,
        ),
      ),
    );
  }
}
