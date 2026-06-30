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
    required this.teamId,
  });

  final String userId;
  final String pseudo;
  final String? teamId;

  bool get hasTeam => teamId != null && teamId!.isNotEmpty;
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

  Future<OnlinePlayerProfile?> ensureReady() async {
    final client = _client;
    if (client == null) return null;

    var session = client.auth.currentSession;
    if (session == null) {
      final response = await client.auth.signInAnonymously();
      session = response.session;
    }

    final user = client.auth.currentUser ?? session?.user;
    if (user == null) return null;

    final existing = await client
        .from('players')
        .select('id, pseudo, team_id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing == null) {
      final pseudo = 'Joueur ${user.id.substring(0, 6)}';
      await client.from('players').insert({
        'id': user.id,
        'pseudo': pseudo,
      });
      return OnlinePlayerProfile(
        userId: user.id,
        pseudo: pseudo,
        teamId: null,
      );
    }

    return OnlinePlayerProfile(
      userId: existing['id'] as String,
      pseudo: existing['pseudo'] as String? ?? 'Joueur',
      teamId: existing['team_id'] as String?,
    );
  }

  Future<OnlinePlayerProfile?> chooseTeam(String teamId) async {
    final client = _client;
    if (client == null) return null;
    final profile = await ensureReady();
    if (profile == null) return null;

    if (profile.hasTeam && profile.teamId != teamId) {
      throw StateError('Ton équipe est déjà choisie pour cette saison.');
    }

    await client
        .from('players')
        .update({'team_id': teamId})
        .eq('id', profile.userId);

    return OnlinePlayerProfile(
      userId: profile.userId,
      pseudo: profile.pseudo,
      teamId: teamId,
    );
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

    final profile = await ensureReady();
    if (profile == null) {
      return const CaptureResult(
        accepted: false,
        message: 'Connexion joueur impossible.',
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
}
