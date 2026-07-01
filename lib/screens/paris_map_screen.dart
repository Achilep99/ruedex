import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/street_database.dart';
import '../models/street_entry.dart';
import '../services/discovery_store.dart';
import '../services/online_game_service.dart';
import '../widgets/paris_street_map.dart';
import '../widgets/rarity_badge.dart';

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
  Set<String> _visibleTeamIds = const {'red', 'blue', 'green', 'yellow'};
  bool _showUnownedStreets = true;
  bool _filtersExpanded = false;
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
      _watchPersonal();
      _watchConquest();
    } else {
      await _loadPersonal();
      _watchPersonal();
    }
  }

  Future<void> _loadPersonal() async {
    Set<String> ids = const {};
    String status = 'Carte personnelle locale';
    if (widget.onlineGameService.isConfigured &&
        widget.onlineGameService.currentUser != null) {
      try {
        ids = await widget.onlineGameService.loadPersonalDiscoveries();
        status = 'Carte personnelle synchronisée';
      } catch (error) {
        status = 'Carte personnelle inaccessible : $error';
      }
    } else if (!widget.onlineGameService.isConfigured) {
      ids = await widget.discoveryStore.loadDiscoveredIds();
    } else {
      status = 'Connecte-toi pour voir ta carte personnelle';
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
      (ids) {
        if (!mounted) return;
        setState(() {
          _discoveredIds = ids;
          _status = _isConquest
              ? 'Conquête synchronisée · collection chargée'
              : 'Carte personnelle synchronisée en direct';
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
    Set<String> personalIds = const {};
    String status = 'Carte de conquête locale';
    if (widget.onlineGameService.isConfigured) {
      try {
        ownership = await widget.onlineGameService.loadStreetOwnership();
        if (widget.onlineGameService.currentUser != null) {
          personalIds = await widget.onlineGameService.loadPersonalDiscoveries();
        }
        status = 'Conquête synchronisée';
      } catch (error) {
        status = 'Conquête inaccessible : $error';
      }
    }
    if (!mounted) return;
    setState(() {
      _discoveredIds = personalIds;
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

  Future<void> _showStreetDetails(StreetEntry street) async {
    final discovered = _discoveredIds.contains(street.id);
    final ownerTeam = widget.onlineGameService.teamById(_onlineOwnership[street.id]);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              discovered ? street.officialName : 'Rue non découverte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            if (_isConquest && ownerTeam != null) ...[
              Row(
                children: [
                  CircleAvatar(radius: 8, backgroundColor: ownerTeam.color),
                  const SizedBox(width: 8),
                  Text('Contrôlée par l’équipe ${ownerTeam.label}'),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (discovered) ...[
              RarityBadge(rarity: street.rarity),
              if (street.arrondissement.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(street.arrondissement),
              ],
              if (street.hasVerifiedOrigin) ...[
                const SizedBox(height: 16),
                Text('Origine officielle', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(street.origin),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _openRoute(street),
                icon: const Icon(Icons.directions),
                label: const Text('Itinéraire'),
              ),
            ] else ...[
              const Text(
                'Tu peux voir la couleur de conquête, mais le nom et l’itinéraire restent cachés tant que tu ne l’as pas découverte personnellement.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openRoute(StreetEntry street) async {
    final center = street.center;
    final query = Uri.encodeComponent('${center.latitude},${center.longitude}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.database.streets.length;
    final displayedCount = _isConquest ? _onlineOwnership.length : _discoveredIds.length;
    final title = _isConquest ? 'Carte de conquête' : 'Ma carte de Paris';
    final subtitle = _isConquest
        ? 'Couleurs des équipes · noms visibles seulement si tu as découvert la rue'
        : 'Ta collection · couleurs de rareté · aucun nom sur la carte';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$displayedCount / $total rues', style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    Flexible(child: Text(_status ?? 'Chargement…', textAlign: TextAlign.end)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: ParisStreetMap(
                  streets: widget.database.streets,
                  bounds: widget.database.bounds,
                  discoveredIds: _isConquest ? const {} : _discoveredIds,
                  teamOwnership: _isConquest ? _onlineOwnership : const {},
                  teamColorResolver: widget.onlineGameService.colorForTeam,
                  visibleTeamIds: _visibleTeamIds,
                  showUnownedStreets: _isConquest ? _showUnownedStreets : true,
                  legendMode: _isConquest ? MapLegendMode.teams : MapLegendMode.rarity,
                  showLegend: !_isConquest,
                  onStreetTap: _showStreetDetails,
                ),
              ),
              if (_isConquest)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _ConquestFilterPanel(
                    expanded: _filtersExpanded,
                    visibleTeamIds: _visibleTeamIds,
                    showUnownedStreets: _showUnownedStreets,
                    onExpandedChanged: (value) => setState(() => _filtersExpanded = value),
                    onTeamChanged: (teamId, enabled) {
                      setState(() {
                        final next = {..._visibleTeamIds};
                        if (enabled) {
                          next.add(teamId);
                        } else {
                          next.remove(teamId);
                        }
                        _visibleTeamIds = next;
                      });
                    },
                    onUnownedChanged: (value) => setState(() => _showUnownedStreets = value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConquestFilterPanel extends StatelessWidget {
  const _ConquestFilterPanel({
    required this.expanded,
    required this.visibleTeamIds,
    required this.showUnownedStreets,
    required this.onExpandedChanged,
    required this.onTeamChanged,
    required this.onUnownedChanged,
  });

  final bool expanded;
  final Set<String> visibleTeamIds;
  final bool showUnownedStreets;
  final ValueChanged<bool> onExpandedChanged;
  final void Function(String teamId, bool enabled) onTeamChanged;
  final ValueChanged<bool> onUnownedChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Filtres de conquête', style: TextStyle(fontWeight: FontWeight.w800))),
                TextButton.icon(
                  onPressed: () => onExpandedChanged(!expanded),
                  icon: Icon(expanded ? Icons.expand_more : Icons.expand_less),
                  label: Text(expanded ? 'Réduire' : 'Ouvrir'),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 7,
                runSpacing: 4,
                children: [
                  for (final team in OnlineGameService.teams)
                    FilterChip(
                      selected: visibleTeamIds.contains(team.id),
                      label: Text(team.label),
                      avatar: CircleAvatar(backgroundColor: team.color),
                      onSelected: (value) => onTeamChanged(team.id, value),
                    ),
                  FilterChip(
                    selected: showUnownedStreets,
                    label: const Text('Non capturées'),
                    avatar: const CircleAvatar(backgroundColor: Colors.grey),
                    onSelected: onUnownedChanged,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
