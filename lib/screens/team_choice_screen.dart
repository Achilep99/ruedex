import 'package:flutter/material.dart';

import '../services/online_game_service.dart';

class TeamChoiceScreen extends StatefulWidget {
  const TeamChoiceScreen({
    required this.onlineGameService,
    super.key,
  });

  final OnlineGameService onlineGameService;

  @override
  State<TeamChoiceScreen> createState() => _TeamChoiceScreenState();
}

class _TeamChoiceScreenState extends State<TeamChoiceScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _choose(String teamId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onlineGameService.chooseTeam(teamId);
      if (mounted) Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir une équipe')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Choisis ta couleur pour la saison.',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pour l’instant, le choix est bloqué après validation. On pourra ajouter des règles plus fines plus tard.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            for (final team in OnlineGameService.teams) ...[
              Card(
                child: ListTile(
                  enabled: !_saving,
                  leading: CircleAvatar(backgroundColor: team.color),
                  title: Text('Équipe ${team.label}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choose(team.id),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
