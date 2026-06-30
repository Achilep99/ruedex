import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/street_database.dart';
import '../services/app_settings_store.dart';
import '../services/discovery_store.dart';
import '../services/online_game_service.dart';
import 'auth_screen.dart';
import 'paris_map_screen.dart';
import 'pokedex_screen.dart';
import 'profile_screen.dart';
import 'scanner_screen.dart';
import 'team_choice_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
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
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Set<String> _discoveredIds = const {};
  OnlinePlayerProfile? _onlineProfile;
  RueDexClan? _clan;
  String? _onlineStatus;
  bool _developerMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final localIds = await widget.discoveryStore.loadDiscoveredIds();
    final developerMode = await widget.settingsStore.loadDeveloperMode();
    OnlinePlayerProfile? profile;
    RueDexClan? clan;
    String? onlineStatus;
    Set<String> discoveredIds = localIds;

    if (widget.onlineGameService.isConfigured) {
      try {
        profile = await widget.onlineGameService.currentProfile();
        if (profile == null) {
          onlineStatus = 'Connecte-toi pour jouer en ligne';
        } else {
          final onlineIds = await widget.onlineGameService.loadPersonalDiscoveries();
          if (onlineIds.isNotEmpty) discoveredIds = onlineIds;
          clan = await widget.onlineGameService.loadMyClan();
          final team = widget.onlineGameService.teamById(profile.teamId);
          onlineStatus = team == null
              ? 'Compte connecté · aucune équipe choisie'
              : 'Compte connecté · équipe ${team.label}';
        }
      } catch (error) {
        onlineStatus = 'Serveur configuré mais inaccessible : $error';
      }
    } else {
      onlineStatus = 'Mode local · Supabase non configuré';
    }

    if (!mounted) return;
    setState(() {
      _discoveredIds = discoveredIds;
      _developerMode = developerMode;
      _onlineProfile = profile;
      _clan = clan;
      _onlineStatus = onlineStatus;
      _loading = false;
    });
  }

  Future<void> _openScanner() async {
    if (widget.onlineGameService.isConfigured) {
      final profile = await widget.onlineGameService.currentProfile();
      if (!mounted) return;
      if (profile == null) {
        await _openAuth();
        return;
      }
      if (!profile.hasTeam) {
        await _chooseTeam();
        return;
      }
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          database: widget.database,
          discoveryStore: widget.discoveryStore,
          onlineGameService: widget.onlineGameService,
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

  Future<void> _openPersonalMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ParisMapScreen(
          database: widget.database,
          discoveryStore: widget.discoveryStore,
          onlineGameService: widget.onlineGameService,
          mode: ParisMapMode.personal,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openConquestMap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ParisMapScreen(
          database: widget.database,
          discoveryStore: widget.discoveryStore,
          onlineGameService: widget.onlineGameService,
          mode: ParisMapMode.conquest,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openAuth() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(onlineGameService: widget.onlineGameService),
      ),
    );
    await _reload();
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(onlineGameService: widget.onlineGameService),
      ),
    );
    await _reload();
  }

  Future<void> _chooseTeam() async {
    if (!widget.onlineGameService.isConfigured) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamChoiceScreen(
          onlineGameService: widget.onlineGameService,
        ),
      ),
    );
    await _reload();
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
    final team = widget.onlineGameService.teamById(_onlineProfile?.teamId);

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
          IconButton(
            tooltip: 'Profil',
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline),
          ),
          if (AppConfig.developerToolsAvailable && _developerMode)
            IconButton(
              tooltip: 'Réglages développeur',
              onPressed: _showSettings,
              icon: const Icon(Icons.science),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Paris devient ton terrain de conquête.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scanne les plaques pour remplir ta collection et recolorer la carte de saison pour ton équipe.',
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
                              _loading ? 'Chargement…' : '$count / $total rues dans ta collection',
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
              const SizedBox(height: 12),
              _OnlineGameCard(
                serviceConfigured: widget.onlineGameService.isConfigured,
                onlineStatus: _onlineStatus,
                profile: _onlineProfile,
                clan: _clan,
                team: team,
                onAuth: _openAuth,
                onChooseTeam: _chooseTeam,
                onProfile: _openProfile,
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
                      onPressed: _openPersonalMap,
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
                      onPressed: _openConquestMap,
                      icon: const Icon(Icons.public),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Conquête'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openPokedex,
                icon: const Icon(Icons.grid_view_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('RueDex'),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Données géographiques : ${widget.database.sourceLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineGameCard extends StatelessWidget {
  const _OnlineGameCard({
    required this.serviceConfigured,
    required this.onlineStatus,
    required this.profile,
    required this.clan,
    required this.team,
    required this.onAuth,
    required this.onChooseTeam,
    required this.onProfile,
  });

  final bool serviceConfigured;
  final String? onlineStatus;
  final OnlinePlayerProfile? profile;
  final RueDexClan? clan;
  final RueDexTeam? team;
  final VoidCallback onAuth;
  final VoidCallback onChooseTeam;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(serviceConfigured ? Icons.cloud_done : Icons.cloud_off),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saison en ligne',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (team != null) CircleAvatar(radius: 10, backgroundColor: team!.color),
              ],
            ),
            const SizedBox(height: 8),
            Text(onlineStatus ?? 'Chargement du serveur…'),
            if (profile != null) ...[
              const SizedBox(height: 8),
              Text('Profil : ${profile!.pseudo}'),
              Text(clan == null ? 'Clan : aucun' : 'Clan : ${clan!.name} [${clan!.tag}]'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (serviceConfigured && profile == null)
                  FilledButton.tonalIcon(
                    onPressed: onAuth,
                    icon: const Icon(Icons.login),
                    label: const Text('Créer / connexion'),
                  ),
                if (serviceConfigured && profile != null && team == null)
                  FilledButton.tonalIcon(
                    onPressed: onChooseTeam,
                    icon: const Icon(Icons.groups),
                    label: const Text('Choisir mon équipe'),
                  ),
                if (serviceConfigured && profile != null)
                  OutlinedButton.icon(
                    onPressed: onProfile,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Profil / clan'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
