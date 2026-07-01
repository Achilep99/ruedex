import 'dart:async';

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
  final _searchController = TextEditingController();
  final _messageController = TextEditingController();
  final _minDiscoveriesController = TextEditingController(text: '0');

  StreamSubscription<List<ClanMessage>>? _messagesSubscription;
  RueDexClan? _clan;
  OnlinePlayerProfile? _profile;
  PlayerScores? _scores;
  List<ClanSummary> _topClans = const [];
  List<ClanSummary> _searchResults = const [];
  List<ClanMemberInfo> _members = const [];
  List<ClanMessage> _messages = const [];
  List<ClanJournalEntry> _journal = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _nameController.dispose();
    _tagController.dispose();
    _searchController.dispose();
    _messageController.dispose();
    _minDiscoveriesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.onlineGameService.currentProfile();
      final clan = profile == null ? null : await widget.onlineGameService.loadMyClan();
      final scores = profile == null ? null : await widget.onlineGameService.loadMyScores();
      final topClans = await widget.onlineGameService.loadTopClans();
      final members = clan == null
          ? const <ClanMemberInfo>[]
          : await widget.onlineGameService.loadClanMembers(clan.id);
      final messages = clan == null
          ? const <ClanMessage>[]
          : await widget.onlineGameService.loadClanMessages(clan.id);
      final journal = clan == null
          ? const <ClanJournalEntry>[]
          : await widget.onlineGameService.loadClanJournal(clan.id);

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _clan = clan;
        _scores = scores;
        _topClans = topClans;
        _members = members;
        _messages = messages;
        _journal = journal;
        _loading = false;
      });
      _watchMessages(clan);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  void _watchMessages(RueDexClan? clan) {
    if (clan == null) return;
    _messagesSubscription = widget.onlineGameService.watchClanMessages(clan.id).listen(
      (messages) {
        if (mounted) {
          setState(() => _messages = messages);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _error = 'Chat coupé : $error');
        }
      },
    );
  }

  Future<void> _createClan() async {
    await _runSaving(() async {
      await widget.onlineGameService.createClan(
        name: _nameController.text,
        tag: _tagController.text,
        minDiscoveries: int.tryParse(_minDiscoveriesController.text.trim()) ?? 0,
      );
    });
  }

  Future<void> _joinClan(String tag) async {
    await _runSaving(() async {
      await widget.onlineGameService.joinClan(tag);
    });
  }

  Future<void> _leaveClan() async {
    await _runSaving(widget.onlineGameService.leaveClan);
  }

  Future<void> _kickMember(ClanMemberInfo member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer du clan ?'),
        content: Text('${member.pseudo} sera retiré du clan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runSaving(() async {
      await widget.onlineGameService.kickClanMember(member.playerId);
    });
  }

  Future<void> _openClanSettings(RueDexClan clan) async {
    final controller = TextEditingController(text: '${clan.minDiscoveries}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paramètres du clan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(clan.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Rues perso minimum pour rejoindre',
                helperText: '0 = clan ouvert aux joueurs de ton équipe',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(context).pop(parsed.clamp(0, 9999));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _runSaving(() async {
      await widget.onlineGameService.updateClanSettings(minDiscoveries: value);
    });
  }

  Future<void> _postMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onlineGameService.postClanMessage(content);
      _messageController.clear();
      if (mounted) {
        setState(() => _saving = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _reportMessage(ClanMessage message) async {
    await _runSaving(() async {
      await widget.onlineGameService.reportClanMessage(
        messageId: message.id,
        reason: 'Signalé depuis l’application',
      );
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message signalé. Il ne sera pas supprimé automatiquement.')),
    );
  }

  Future<void> _searchClans(String value) async {
    setState(() => _searchText = value.trim());
    final results = await widget.onlineGameService.searchClans(value);
    if (mounted && _searchText == value.trim()) {
      setState(() => _searchResults = results);
    }
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
      _messageController.clear();
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
      appBar: AppBar(title: const Text('Clans')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              _TopClansCard(
                clans: _topClans,
                onlineGameService: widget.onlineGameService,
              ),
              const SizedBox(height: 18),
              if (profile == null) ...[
                const Text('Connecte-toi avant d’utiliser les clans.'),
              ] else if (!profile.hasTeam) ...[
                const Text('Choisis une équipe avant de créer ou rejoindre un clan.'),
              ] else if (clan != null) ...[
                _MyClanCard(
                  clan: clan,
                  teamLabel: team?.label ?? clan.teamId,
                  teamColor: team?.color ?? Colors.grey,
                  scores: _scores,
                ),
                if (clan.isOwner) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _saving ? null : () => _openClanSettings(clan),
                    icon: const Icon(Icons.tune),
                    label: const Text('Paramètres du clan'),
                  ),
                ],
                const SizedBox(height: 14),
                _ClanJournalCard(entries: _journal),
                const SizedBox(height: 14),
                _ClanMembersCard(
                  members: _members,
                  currentUserId: profile.userId,
                  canKick: clan.isOwner,
                  onKick: _kickMember,
                ),
                const SizedBox(height: 14),
                _ClanChatCard(
                  messages: _messages,
                  messageController: _messageController,
                  saving: _saving,
                  onSend: _postMessage,
                  onReport: _reportMessage,
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
                  controller: _searchController,
                  enabled: !_saving,
                  onChanged: _searchClans,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Rechercher un clan',
                    helperText: 'Exemple : tape “puissance” pour voir les clans qui commencent par ce nom ou ce tag.',
                  ),
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final clan in _searchResults)
                    _ClanSearchTile(
                      clan: clan,
                      teamLabel: widget.onlineGameService.teamById(clan.teamId)?.label ?? clan.teamId,
                      teamColor: widget.onlineGameService.colorForTeam(clan.teamId) ?? Colors.grey,
                      onJoin: _saving ? null : () => _joinClan(clan.tag),
                    ),
                ],
                const SizedBox(height: 20),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _minDiscoveriesController,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Rues perso minimum pour rejoindre',
                    helperText: '0 = clan ouvert à tous les joueurs de ton équipe',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _createClan,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer le clan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopClansCard extends StatelessWidget {
  const _TopClansCard({
    required this.clans,
    required this.onlineGameService,
  });

  final List<ClanSummary> clans;
  final OnlineGameService onlineGameService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Meilleurs clans', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (clans.isEmpty)
              const Text('Aucun clan classé pour le moment.')
            else
              for (var index = 0; index < clans.length; index++)
                _ClanRankTile(
                  rank: index + 1,
                  clan: clans[index],
                  teamColor: onlineGameService.colorForTeam(clans[index].teamId) ?? Colors.grey,
                ),
          ],
        ),
      ),
    );
  }
}

class _ClanRankTile extends StatelessWidget {
  const _ClanRankTile({
    required this.rank,
    required this.clan,
    required this.teamColor,
  });

  final int rank;
  final ClanSummary clan;
  final Color teamColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: teamColor,
        child: Text('$rank'),
      ),
      title: Text('${clan.name} [${clan.tag}]'),
      subtitle: Text('Niveau ${clan.level} · ${clan.memberCount} membre(s)'),
      trailing: Text('${clan.score} pts'),
    );
  }
}

class _MyClanCard extends StatelessWidget {
  const _MyClanCard({
    required this.clan,
    required this.teamLabel,
    required this.teamColor,
    required this.scores,
  });

  final RueDexClan clan;
  final String teamLabel;
  final Color teamColor;
  final PlayerScores? scores;

  @override
  Widget build(BuildContext context) {
    final playerScores = scores;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: teamColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clan.name, style: Theme.of(context).textTheme.headlineSmall),
                      Text('[${clan.tag}] · équipe $teamLabel'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('${clan.memberCount} membre(s) · rôle : ${clan.role}'),
            Text('Score clan : ${clan.score} pts · niveau ${clan.level}'),
            Text('Pré-requis : ${clan.minDiscoveries} rues découvertes'),
            if (playerScores != null) ...[
              const Divider(height: 24),
              Text('Ton score collection : ${playerScores.personalScore}'),
              Text('Ton score conquête : ${playerScores.conquestScore}'),
              Text('Ta contribution clan : ${playerScores.clanScore}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClanJournalCard extends StatelessWidget {
  const _ClanJournalCard({required this.entries});

  final List<ClanJournalEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Journal du clan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final entry in entries.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('• ${entry.message}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClanMembersCard extends StatelessWidget {
  const _ClanMembersCard({
    required this.members,
    required this.currentUserId,
    required this.canKick,
    required this.onKick,
  });

  final List<ClanMemberInfo> members;
  final String currentUserId;
  final bool canKick;
  final ValueChanged<ClanMemberInfo> onKick;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Membres', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final member in members)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(member.role == 'owner' ? Icons.workspace_premium : Icons.person),
                title: Text(member.pseudo),
                subtitle: Text(member.role),
                trailing: canKick && member.playerId != currentUserId && member.role != 'owner'
                    ? IconButton(
                        tooltip: 'Supprimer du clan',
                        onPressed: () => onKick(member),
                        icon: const Icon(Icons.person_remove_alt_1_outlined),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ClanChatCard extends StatelessWidget {
  const _ClanChatCard({
    required this.messages,
    required this.messageController,
    required this.saving,
    required this.onSend,
    required this.onReport,
  });

  final List<ClanMessage> messages;
  final TextEditingController messageController;
  final bool saving;
  final VoidCallback onSend;
  final ValueChanged<ClanMessage> onReport;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat du clan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Visible : 50 derniers messages ou 2 jours. Les messages signalés sont conservés.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: messages.isEmpty
                  ? const Center(child: Text('Aucun message.'))
                  : ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(message.pseudo),
                          subtitle: Text(message.content),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'report') onReport(message);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'report',
                                child: Text('Signaler'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    enabled: !saving,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Message au clan'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: saving ? null : onSend,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClanSearchTile extends StatelessWidget {
  const _ClanSearchTile({
    required this.clan,
    required this.teamLabel,
    required this.teamColor,
    required this.onJoin,
  });

  final ClanSummary clan;
  final String teamLabel;
  final Color teamColor;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: teamColor),
        title: Text('${clan.name} [${clan.tag}]'),
        subtitle: Text(
          '$teamLabel · ${clan.score} pts · pré-requis ${clan.minDiscoveries} rues',
        ),
        trailing: FilledButton(
          onPressed: onJoin,
          child: const Text('Rejoindre'),
        ),
      ),
    );
  }
}
