import 'package:flutter/material.dart';

import '../services/online_game_service.dart';

class ClanScreen extends StatefulWidget {
  const ClanScreen({required this.onlineGameService, super.key});

  final OnlineGameService onlineGameService;

  @override
  State<ClanScreen> createState() => _ClanScreenState();
}

class _ClanScreenState extends State<ClanScreen> {
  final _nameController = TextEditingController();
  final _tagController = TextEditingController();
  RueDexClan? _clan;
  OnlinePlayerProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.onlineGameService.currentProfile();
      final clan = profile == null ? null : await widget.onlineGameService.loadMyClan();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _clan = clan;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _createClan() async {
    await _runSaving(() async {
      await widget.onlineGameService.createClan(
        name: _nameController.text,
        tag: _tagController.text,
      );
    });
  }

  Future<void> _joinClan() async {
    await _runSaving(() async {
      await widget.onlineGameService.joinClan(_tagController.text);
    });
  }

  Future<void> _leaveClan() async {
    await _runSaving(widget.onlineGameService.leaveClan);
  }

  Future<void> _runSaving(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      _nameController.clear();
      _tagController.clear();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final team = widget.onlineGameService.teamById(profile?.teamId);
    final clan = _clan;

    return Scaffold(
      appBar: AppBar(title: const Text('Clan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (profile == null) ...[
              const Text('Connecte-toi avant d’utiliser les clans.'),
            ] else if (!profile.hasTeam) ...[
              const Text('Choisis une équipe avant de créer ou rejoindre un clan.'),
            ] else if (clan != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundColor: team?.color ?? Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(clan.name, style: Theme.of(context).textTheme.headlineSmall),
                                Text('[${clan.tag}] · équipe ${team?.label ?? clan.teamId}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('${clan.memberCount} membre(s)'),
                      Text('Ton rôle : ${clan.role}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _saving ? null : _leaveClan,
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Quitter le clan'),
              ),
            ] else ...[
              Text(
                'Créer ou rejoindre un clan',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text('Les clans sont liés à ton équipe ${team?.label ?? ''}. Tu ne peux rejoindre qu’un clan de ta couleur.'),
              const SizedBox(height: 18),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Nom du clan',
                  helperText: 'Exemple : Les Chasseurs du 11e',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Tag / code du clan',
                  helperText: 'Exemple : LCD11',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _createClan,
                icon: const Icon(Icons.add),
                label: const Text('Créer le clan'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _joinClan,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Rejoindre avec ce tag'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
