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
  });

  final String id;
  final String name;
  final String tag;
  final String teamId;
  final String role;
  final int memberCount;
}

class CaptureResult {
  const CaptureResult({
    required this.accepted,
    required this.message,
    this.teamId,
  });

  final bool accepted;
  final String message;
  final String? teamId;
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
    final data = response as Map<String, dynamic>;
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
        .stream(primaryKey: ['season_id', 'player_id', 'street_id'])
        .map(
          (rows) => {
            for (final row in rows)
              if (row['season_id'] == resolvedSeasonId && row['player_id'] == user.id)
                row['street_id'] as String,
          },
        );
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
        .stream(primaryKey: ['season_id', 'street_id'])
        .map(
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

    final data = response as Map<String, dynamic>;
    return CaptureResult(
      accepted: data['accepted'] as bool? ?? false,
      message: data['message'] as String? ?? 'Capture envoyée.',
      teamId: data['team_id'] as String?,
    );
  }

  Future<RueDexClan?> loadMyClan() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;

    final row = await client
        .from('clan_members')
        .select('role, clans(id, name, tag, team_id)')
        .eq('player_id', user.id)
        .maybeSingle();
    if (row == null) return null;

    final clan = row['clans'] as Map<String, dynamic>?;
    if (clan == null) return null;
    final count = await _clanMemberCount(clan['id'] as String);
    return RueDexClan(
      id: clan['id'] as String,
      name: clan['name'] as String,
      tag: clan['tag'] as String,
      teamId: clan['team_id'] as String,
      role: row['role'] as String? ?? 'member',
      memberCount: count,
    );
  }

  Future<RueDexClan> createClan({
    required String name,
    required String tag,
  }) async {
    final client = _requireClient();
    final response = await client.rpc(
      'create_clan',
      params: {'p_name': name.trim(), 'p_tag': tag.trim()},
    );
    final data = response as Map<String, dynamic>;
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
    final data = response as Map<String, dynamic>;
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
    final data = response as Map<String, dynamic>;
    if (data['accepted'] != true) {
      throw StateError(data['message'] as String? ?? 'Départ impossible.');
    }
  }

  Future<int> _clanMemberCount(String clanId) async {
    final client = _requireClient();
    final rows = await client
        .from('clan_members')
        .select('player_id')
        .eq('clan_id', clanId);
    return (rows as List<dynamic>).length;
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
}
