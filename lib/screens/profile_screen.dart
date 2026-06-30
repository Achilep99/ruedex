import 'package:flutter/material.dart';

import '../services/online_game_service.dart';
import 'auth_screen.dart';
import 'clan_screen.dart';
import 'team_choice_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.onlineGameService, super.key});

  final OnlineGameService onlineGameService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  OnlinePlayerProfile? _profile;
  RueDexClan? _clan;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAuth() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(onlineGameService: widget.onlineGameService),
      ),
    );
    await _load();
  }

  Future<void> _chooseTeam() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamChoiceScreen(onlineGameService: widget.onlineGameService),
      ),
    );
    await _load();
  }

  Future<void> _openClan() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClanScreen(onlineGameService: widget.onlineGameService),
      ),
    );
    await _load();
  }

  Future<void> _editPseudo() async {
    final controller = TextEditingController(text: _profile?.pseudo ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le pseudo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Pseudo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await widget.onlineGameService.updatePseudo(result);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _signOut() async {
    await widget.onlineGameService.signOut();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final team = widget.onlineGameService.teamById(profile?.teamId);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (!widget.onlineGameService.isConfigured) ...[
              const _InfoCard(
                icon: Icons.cloud_off,
                title: 'Serveur non configuré',
                body: 'Ajoute les clés Supabase dans GitHub pour activer les comptes.',
              ),
            ] else if (profile == null) ...[
              const _InfoCard(
                icon: Icons.person_add_alt_1,
                title: 'Aucun compte connecté',
                body: 'Crée un compte pour choisir ton équipe, capturer des rues en ligne et rejoindre un clan.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _openAuth,
                icon: const Icon(Icons.login),
                label: const Text('Créer un compte / connexion'),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: team?.color ?? Theme.of(context).colorScheme.primary,
                            child: Text(
                              profile.pseudo.isEmpty ? '?' : profile.pseudo.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.pseudo, style: Theme.of(context).textTheme.headlineSmall),
                                Text(profile.email ?? 'Compte RueDex'),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Modifier le pseudo',
                            onPressed: _editPseudo,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(backgroundColor: team?.color ?? Colors.grey),
                        title: Text(team == null ? 'Aucune équipe' : 'Équipe ${team.label}'),
                        subtitle: const Text('Choix verrouillé pour la saison'),
                        trailing: team == null ? const Icon(Icons.chevron_right) : null,
                        onTap: team == null ? _chooseTeam : null,
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(_clan == null ? 'Aucun clan' : '${_clan!.name} [${_clan!.tag}]'),
                        subtitle: Text(_clan == null
                            ? 'Créer ou rejoindre un clan'
                            : '${_clan!.memberCount} membre(s) · rôle ${_clan!.role}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openClan,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Déconnexion'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
