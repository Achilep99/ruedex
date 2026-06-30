import 'dart:async';
import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/match_candidate.dart';

class RueDexTeam {
  const RueDexTeam({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
}

class OnlinePlayerProfile {
  const OnlinePlayerProfile({
    required this.userId,
    required this.pseudo,
    required this.email,
    required this.teamId,
    required this.clanId,
  });

  final String userId;
  final String pseudo;
  final String? email;
  final String? teamId;
  final String? clanId;

  bool get hasTeam => teamId != null && teamId!.isNotEmpty;
}

class RueDexClan {
  const RueDexClan({
    required this.id,
    required this.name,
    required this.tag,
    required this.teamId,
    required this.role,
    required this.memberCount,
    required this.minDiscoveries,
    required this.score,
    required this.level,
  });

  final String id;
  final String name;
  final String tag;
  final String teamId;
  final String role;
  final int memberCount;
  final int minDiscoveries;
  final int score;
  final int level;

  bool get isOwner => role == 'owner';
}

class ClanSummary {
  const ClanSummary({
    required this.id,
    required this.name,
    required this.tag,
    required this.teamId,
    required this.memberCount,
    required this.minDiscoveries,
    required this.score,
    required this.level,
  });

  final String id;
  final String name;
  final String tag;
  final String teamId;
  final int memberCount;
  final int minDiscoveries;
  final int score;
  final int level;
}

class ClanMemberInfo {
  const ClanMemberInfo({
    required this.playerId,
    required this.pseudo,
    required this.role,
    required this.joinedAt,
  });

  final String playerId;
  final String pseudo;
  final String role;
  final DateTime? joinedAt;
}

class ClanMessage {
  const ClanMessage({
    required this.id,
    required this.clanId,
    required this.playerId,
    required this.pseudo,
    required this.content,
    required this.createdAt,
    required this.reported,
  });

  final String id;
  final String clanId;
  final String playerId;
  final String pseudo;
  final String content;
  final DateTime? createdAt;
  final bool reported;
}

class ClanJournalEntry {
  const ClanJournalEntry({
    required this.id,
    required this.clanId,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String clanId;
  final String message;
  final DateTime? createdAt;
}

class PlayerScores {
  const PlayerScores({
    required this.personalScore,
    required this.conquestScore,
    required this.clanScore,
    required this.personalDiscoveries,
    required this.conquestCaptures,
  });

  final int personalScore;
  final int conquestScore;
  final int clanScore;
  final int personalDiscoveries;
  final int conquestCaptures;
}

class CaptureResult {
  const CaptureResult({
    required this.accepted,
    required this.message,
    this.teamId,
    this.personalDiscoveryNew = false,
  });

  final bool accepted;
  final String message;
  final String? teamId;
  final bool personalDiscoveryNew;
}

class OnlineGameService {
  OnlineGameService();

  static const List<RueDexTeam> teams = [
    RueDexTeam(id: 'red', label: 'Rouge', color: Color(0xFFE74C3C)),
    RueDexTeam(id: 'blue', label: 'Bleue', color: Color(0xFF3498DB)),
    RueDexTeam(id: 'green', label: 'Verte', color: Color(0xFF2ECC71)),
    RueDexTeam(id: 'yellow', label: 'Jaune', color: Color(0xFFF1C40F)),
  ];

  bool get isConfigured => AppConfig.supabaseConfigured;

  SupabaseClient? get _client {
    if (!isConfigured) return null;
    return Supabase.instance.client;
  }

  RueDexTeam? teamById(String? id) {
    if (id == null) return null;
    for (final team in teams) {
      if (team.id == id) return team;
    }
    return null;
  }

  Color? colorForTeam(String? id) => teamById(id)?.color;

  User? get currentUser => _client?.auth.currentUser;

  Future<OnlinePlayerProfile?> currentProfile() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    return _loadOrCreateProfile(user);
  }

  Future<OnlinePlayerProfile?> refreshProfile() => currentProfile();

  Future<OnlinePlayerProfile> signUpWithEmail({
    required String email,
    required String password,
    required String pseudo,
  }) async {
    final client = _requireClient();
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'pseudo': pseudo.trim()},
    );
    final user = response.user ?? client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw StateError(
        'Compte créé. Si Supabase demande une confirmation email, valide le mail puis connecte-toi.',
      );
    }
    return _loadOrCreateProfile(user, preferredPseudo: pseudo.trim());
  }

  Future<OnlinePlayerProfile> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user ?? client.auth.currentUser;
    if (user == null) {
      throw StateError('Connexion impossible.');
    }
    return _loadOrCreateProfile(user);
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
  }

  Future<OnlinePlayerProfile> updatePseudo(String pseudo) async {
    final client = _requireClient();
    final user = _requireUser(client);
    final cleanPseudo = _cleanPseudo(pseudo);
    await client.from('players').update({
      'pseudo': cleanPseudo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);
    return _loadOrCreateProfile(user);
  }

  Future<OnlinePlayerProfile> _loadOrCreateProfile(
    User user, {
    String? preferredPseudo,
  }) async {
    final client = _requireClient();
    final existing = await client
        .from('players')
        .select('id, pseudo, team_id, clan_id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing == null) {
      final pseudo = _cleanPseudo(
        preferredPseudo ??
            user.userMetadata?['pseudo']?.toString() ??
            user.email?.split('@').first ??
            'Joueur ${user.id.substring(0, 6)}',
      );
      await client.from('players').insert({
        'id': user.id,
        'pseudo': pseudo,
      });
      return OnlinePlayerProfile(
        userId: user.id,
        pseudo: pseudo,
        email: user.email,
        teamId: null,
        clanId: null,
      );
    }

    return OnlinePlayerProfile(
      userId: existing['id'] as String,
      pseudo: existing['pseudo'] as String? ?? 'Joueur',
      email: user.email,
      teamId: existing['team_id'] as String?,
      clanId: existing['clan_id'] as String?,
    );
  }

  Future<OnlinePlayerProfile> chooseTeam(String teamId) async {
    final client = _requireClient();
    final user = _requireUser(client);
    final response = await client.rpc(
      'choose_team',
      params: {'p_team_id': teamId},
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Équipe refusée.');
    }
    return _loadOrCreateProfile(user);
  }

  Future<String?> activeSeasonId() async {
    final client = _client;
    if (client == null) return null;
    final season = await client
        .from('seasons')
        .select('id')
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
    return season?['id'] as String?;
  }

  Future<Set<String>> loadPersonalDiscoveries({String? seasonId}) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return const {};
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) return const {};

    final rows = await client
        .from('personal_discoveries')
        .select('street_id')
        .eq('season_id', resolvedSeasonId)
        .eq('player_id', user.id);

    return {
      for (final row in rows as List<dynamic>) row['street_id'] as String,
    };
  }

  Stream<Set<String>> watchPersonalDiscoveries({String? seasonId}) async* {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      yield const {};
      return;
    }
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) {
      yield const {};
      return;
    }

    yield* client
        .from('personal_discoveries')
        .stream(primaryKey: ['season_id', 'player_id', 'street_id']).map(
      (rows) => {
        for (final row in rows)
          if (row['season_id'] == resolvedSeasonId && row['player_id'] == user.id)
            row['street_id'] as String,
      },
    );
  }

  Future<Map<String, DateTime?>> loadPersonalDiscoveryDates({String? seasonId}) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return const {};
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) return const {};

    final rows = await client
        .from('personal_discoveries')
        .select('street_id, discovered_at')
        .eq('season_id', resolvedSeasonId)
        .eq('player_id', user.id);

    return {
      for (final row in rows as List<dynamic>)
        row['street_id'] as String: _parseDate(row['discovered_at']),
    };
  }

  Future<Map<String, String>> loadStreetOwnership({String? seasonId}) async {
    final client = _client;
    if (client == null) return const {};
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) return const {};

    final rows = await client
        .from('street_ownership')
        .select('street_id, team_id')
        .eq('season_id', resolvedSeasonId);

    return {
      for (final row in rows as List<dynamic>)
        row['street_id'] as String: row['team_id'] as String,
    };
  }

  Stream<Map<String, String>> watchStreetOwnership({String? seasonId}) async* {
    final client = _client;
    if (client == null) {
      yield const {};
      return;
    }
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) {
      yield const {};
      return;
    }

    yield* client
        .from('street_ownership')
        .stream(primaryKey: ['season_id', 'street_id']).map(
      (rows) => {
        for (final row in rows)
          if (row['season_id'] == resolvedSeasonId)
            row['street_id'] as String: row['team_id'] as String,
      },
    );
  }

  Future<CaptureResult> captureStreet({
    required MatchCandidate candidate,
    required double plateScore,
  }) async {
    final client = _client;
    if (client == null) {
      return const CaptureResult(
        accepted: false,
        message: 'Mode local : serveur non configuré.',
      );
    }

    final profile = await currentProfile();
    if (profile == null) {
      return const CaptureResult(
        accepted: false,
        message: 'Connecte-toi avant de capturer une rue.',
      );
    }
    if (!profile.hasTeam) {
      return const CaptureResult(
        accepted: false,
        message: 'Choisis une équipe avant de capturer une rue.',
      );
    }

    final seasonId = await activeSeasonId();
    if (seasonId == null) {
      return const CaptureResult(
        accepted: false,
        message: 'Aucune saison active.',
      );
    }

    final response = await client.rpc(
      'capture_street',
      params: {
        'p_season_id': seasonId,
        'p_street_id': candidate.street.id,
        'p_distance_meters': candidate.distanceMeters,
        'p_ocr_score': candidate.textScore,
        'p_plate_score': plateScore,
      },
    );

    final data = Map<String, dynamic>.from(response as Map);
    return CaptureResult(
      accepted: data['accepted'] as bool? ?? false,
      message: data['message'] as String? ?? 'Capture envoyée.',
      teamId: data['team_id'] as String?,
      personalDiscoveryNew: data['personal_discovery_new'] as bool? ?? false,
    );
  }

  Future<PlayerScores?> loadMyScores({String? seasonId}) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    final resolvedSeasonId = seasonId ?? await activeSeasonId();
    if (resolvedSeasonId == null) return null;
    final row = await client
        .from('player_scores')
        .select('personal_score, conquest_score, clan_score, personal_discoveries, conquest_captures')
        .eq('season_id', resolvedSeasonId)
        .eq('player_id', user.id)
        .maybeSingle();
    if (row == null) {
      return const PlayerScores(
        personalScore: 0,
        conquestScore: 0,
        clanScore: 0,
        personalDiscoveries: 0,
        conquestCaptures: 0,
      );
    }
    return PlayerScores(
      personalScore: _asInt(row['personal_score']),
      conquestScore: _asInt(row['conquest_score']),
      clanScore: _asInt(row['clan_score']),
      personalDiscoveries: _asInt(row['personal_discoveries']),
      conquestCaptures: _asInt(row['conquest_captures']),
    );
  }

  Future<RueDexClan?> loadMyClan() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;

    final row = await client
        .from('clan_members')
        .select(
          'role, clans(id, name, tag, team_id, min_discoveries, score, level)',
        )
        .eq('player_id', user.id)
        .maybeSingle();
    if (row == null) return null;

    final clan = row['clans'] as Map<String, dynamic>?;
    if (clan == null) return null;
    final count = await clanMemberCount(clan['id'] as String);
    return RueDexClan(
      id: clan['id'] as String,
      name: clan['name'] as String,
      tag: clan['tag'] as String,
      teamId: clan['team_id'] as String,
      role: row['role'] as String? ?? 'member',
      memberCount: count,
      minDiscoveries: _asInt(clan['min_discoveries']),
      score: _asInt(clan['score']),
      level: _asInt(clan['level'], fallback: 1),
    );
  }

  Future<RueDexClan> createClan({
    required String name,
    required String tag,
    required int minDiscoveries,
  }) async {
    final client = _requireClient();
    final response = await client.rpc(
      'create_clan',
      params: {
        'p_name': name.trim(),
        'p_tag': tag.trim(),
        'p_min_discoveries': minDiscoveries,
      },
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Clan refusé.');
    }
    final clan = await loadMyClan();
    if (clan == null) throw StateError('Clan créé mais introuvable.');
    return clan;
  }

  Future<RueDexClan> joinClan(String tag) async {
    final client = _requireClient();
    final response = await client.rpc(
      'join_clan',
      params: {'p_tag': tag.trim()},
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Clan refusé.');
    }
    final clan = await loadMyClan();
    if (clan == null) throw StateError('Clan rejoint mais introuvable.');
    return clan;
  }

  Future<void> leaveClan() async {
    final client = _requireClient();
    final response = await client.rpc('leave_clan');
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Départ impossible.');
    }
  }

  Future<void> kickClanMember(String playerId) async {
    final client = _requireClient();
    final response = await client.rpc(
      'kick_clan_member',
      params: {'p_player_id': playerId},
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Expulsion impossible.');
    }
  }

  Future<List<ClanMemberInfo>> loadClanMembers(String clanId) async {
    final client = _requireClient();
    final rows = await client
        .from('clan_members')
        .select('player_id, role, joined_at, players(pseudo)')
        .eq('clan_id', clanId)
        .order('joined_at');
    return [
      for (final row in rows as List<dynamic>)
        ClanMemberInfo(
          playerId: row['player_id'] as String,
          pseudo: ((row['players'] as Map<String, dynamic>?)?['pseudo'] as String?) ?? 'Joueur',
          role: row['role'] as String? ?? 'member',
          joinedAt: _parseDate(row['joined_at']),
        ),
    ];
  }

  Future<int> clanMemberCount(String clanId) async {
    final client = _requireClient();
    final rows = await client
        .from('clan_members')
        .select('player_id')
        .eq('clan_id', clanId);
    return (rows as List<dynamic>).length;
  }

  Future<List<ClanSummary>> loadTopClans({int limit = 10}) async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client
        .from('clans')
        .select('id, name, tag, team_id, min_discoveries, score, level')
        .order('score', ascending: false)
        .limit(limit);
    return _parseClanSummaries(rows as List<dynamic>);
  }

  Future<List<ClanSummary>> searchClans(String prefix, {int limit = 20}) async {
    final client = _client;
    if (client == null) return const [];
    final query = prefix.trim();
    if (query.isEmpty) return loadTopClans(limit: limit);
    final pattern = '${query.replaceAll('%', '').replaceAll('_', '')}%';
    final tagPattern = '${query.toUpperCase().replaceAll('%', '').replaceAll('_', '')}%';
    final rows = await client
        .from('clans')
        .select('id, name, tag, team_id, min_discoveries, score, level')
        .or('name.ilike.$pattern,tag.ilike.$tagPattern')
        .order('score', ascending: false)
        .limit(limit);
    return _parseClanSummaries(rows as List<dynamic>);
  }

  Future<List<ClanMessage>> loadClanMessages(String clanId) async {
    final client = _requireClient();
    final rows = await client
        .from('clan_messages')
        .select('id, clan_id, player_id, content, created_at, reported, players(pseudo)')
        .eq('clan_id', clanId)
        .order('created_at', ascending: false)
        .limit(50);
    return [
      for (final row in (rows as List<dynamic>).reversed)
        _parseClanMessage(row as Map<String, dynamic>),
    ];
  }

  Stream<List<ClanMessage>> watchClanMessages(String clanId) async* {
    final client = _client;
    if (client == null) {
      yield const [];
      return;
    }
    yield* client.from('clan_messages').stream(primaryKey: ['id']).map(
      (rows) {
        final messages = [
          for (final row in rows)
            if (row['clan_id'] == clanId) _parseClanMessage(row),
        ]
          ..sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aTime.compareTo(bTime);
          });
        return messages.takeLast(50).toList(growable: false);
      },
    );
  }

  Future<void> postClanMessage(String content) async {
    final client = _requireClient();
    final response = await client.rpc(
      'post_clan_message',
      params: {'p_content': content.trim()},
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Message refusé.');
    }
  }

  Future<void> reportClanMessage({
    required String messageId,
    required String reason,
  }) async {
    final client = _requireClient();
    final response = await client.rpc(
      'report_clan_message',
      params: {'p_message_id': messageId, 'p_reason': reason.trim()},
    );
    final data = Map<String, dynamic>.from(response as Map);
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Signalement refusé.');
    }
  }

  Future<List<ClanJournalEntry>> loadClanJournal(String clanId) async {
    final client = _requireClient();
    final rows = await client
        .from('clan_journal')
        .select('id, clan_id, message, created_at')
        .eq('clan_id', clanId)
        .order('created_at', ascending: false)
        .limit(20);
    return [
      for (final row in rows as List<dynamic>)
        ClanJournalEntry(
          id: row['id'] as String,
          clanId: row['clan_id'] as String,
          message: row['message'] as String? ?? '',
          createdAt: _parseDate(row['created_at']),
        ),
    ];
  }

  List<ClanSummary> _parseClanSummaries(List<dynamic> rows) {
    return [
      for (final row in rows)
        ClanSummary(
          id: row['id'] as String,
          name: row['name'] as String? ?? 'Clan',
          tag: row['tag'] as String? ?? '',
          teamId: row['team_id'] as String? ?? '',
          memberCount: _asInt(row['member_count']),
          minDiscoveries: _asInt(row['min_discoveries']),
          score: _asInt(row['score']),
          level: _asInt(row['level'], fallback: 1),
        ),
    ];
  }

  ClanMessage _parseClanMessage(Map<String, dynamic> row) {
    return ClanMessage(
      id: row['id'] as String,
      clanId: row['clan_id'] as String,
      playerId: row['player_id'] as String,
      pseudo: ((row['players'] as Map<String, dynamic>?)?['pseudo'] as String?) ?? 'Joueur',
      content: row['content'] as String? ?? '',
      createdAt: _parseDate(row['created_at']),
      reported: row['reported'] as bool? ?? false,
    );
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) throw StateError('Supabase n’est pas configuré.');
    return client;
  }

  User _requireUser(SupabaseClient client) {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Connecte-toi d’abord.');
    return user;
  }

  String _cleanPseudo(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length < 3) return 'Joueur';
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

extension _TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
