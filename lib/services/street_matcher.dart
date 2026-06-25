import 'dart:math' as math;

import '../models/geo_point.dart';
import '../models/match_candidate.dart';
import '../models/street_entry.dart';
import 'geometry_service.dart';
import 'text_normalizer.dart';

class StreetMatcher {
  const StreetMatcher({
    this.maximumSearchRadiusMeters = 180,
    this.minimumTextScore = 0.82,
    this.minimumCoverage = 0.80,
    this.minimumMargin = 0.10,
  });

  final double maximumSearchRadiusMeters;
  final double minimumTextScore;
  final double minimumCoverage;
  final double minimumMargin;

  List<MatchCandidate> findCandidates({
    required String recognizedText,
    required List<StreetEntry> streets,
    double? latitude,
    double? longitude,
    double? gpsAccuracyMeters,
    int maximumResults = 5,
  }) {
    final fragments = TextNormalizer.fragments(recognizedText);
    if (fragments.isEmpty) return const [];

    final userPoint = latitude == null || longitude == null
        ? null
        : GeoPoint(latitude, longitude);
    final allowedRadius = validationRadius(gpsAccuracyMeters);
    final searchRadius = math.max(maximumSearchRadiusMeters, allowedRadius * 1.7);
    final candidates = <MatchCandidate>[];

    for (final street in streets) {
      double? distance;
      if (userPoint != null) {
        if (!street.bounds.containsRoughly(userPoint, searchRadius)) continue;
        distance = GeometryService.distanceToStreetMeters(userPoint, street);
        if (!distance.isFinite || distance > searchRadius) continue;
      }

      final score = _bestTextScore(fragments, street);
      if (score.textScore < 0.20) continue;

      final locationScore = distance == null
          ? 0.5
          : (1 - distance / searchRadius).clamp(0.0, 1.0).toDouble();
      // Le GPS est un filtre dur. Il ne doit jamais transformer un mauvais OCR
      // en bonne réponse. Il sert seulement à départager les rues proches.
      final finalScore = score.textScore * 0.94 + locationScore * 0.06;

      candidates.add(
        MatchCandidate(
          street: street,
          textScore: score.textScore,
          tokenCoverage: score.coverage,
          phraseScore: score.phraseScore,
          locationScore: locationScore,
          finalScore: finalScore,
          distanceMeters: distance,
          matchedFragment: score.fragment,
          roadTypeCompatible: score.roadTypeCompatible,
        ),
      );
    }

    candidates.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return candidates.take(maximumResults).toList(growable: false);
  }

  MatchDecision decide(
    List<MatchCandidate> candidates, {
    double? gpsAccuracyMeters,
    bool requireGps = true,
  }) {
    if (candidates.isEmpty) {
      return const MatchDecision(
        accepted: false,
        best: null,
        reason: 'Aucun nom de rue crédible détecté.',
        margin: 0,
      );
    }

    final best = candidates.first;
    final secondScore = candidates.length > 1 ? candidates[1].finalScore : 0.0;
    final margin = best.finalScore - secondScore;
    final radius = validationRadius(gpsAccuracyMeters);

    if (requireGps && best.distanceMeters == null) {
      return MatchDecision(
        accepted: false,
        best: best,
        reason: 'Position GPS absente.',
        margin: margin,
      );
    }
    if (best.distanceMeters != null && best.distanceMeters! > radius) {
      return MatchDecision(
        accepted: false,
        best: best,
        reason: 'La plaque reconnue ne correspond pas à une rue assez proche.',
        margin: margin,
      );
    }
    if (!best.roadTypeCompatible) {
      return MatchDecision(
        accepted: false,
        best: best,
        reason: 'Le type de voie lu ne correspond pas.',
        margin: margin,
      );
    }
    if (best.textScore < minimumTextScore || best.tokenCoverage < minimumCoverage) {
      return MatchDecision(
        accepted: false,
        best: best,
        reason: 'Le nom complet n’est pas suffisamment reconnu.',
        margin: margin,
      );
    }
    if (candidates.length > 1 && margin < minimumMargin) {
      return MatchDecision(
        accepted: false,
        best: best,
        reason: 'Deux rues sont trop proches dans le classement.',
        margin: margin,
      );
    }

    return MatchDecision(
      accepted: true,
      best: best,
      reason: 'Correspondance fiable.',
      margin: margin,
    );
  }

  double validationRadius(double? gpsAccuracyMeters) {
    final accuracy = (gpsAccuracyMeters ?? 20).clamp(5.0, 90.0).toDouble();
    return math.max(45.0, math.min(130.0, accuracy + 35.0));
  }

  _TextScore _bestTextScore(List<String> fragments, StreetEntry street) {
    var best = const _TextScore.zero();
    for (final fragment in fragments) {
      for (final possibleName in street.allNames) {
        final score = _scoreFragment(fragment, possibleName, street.roadType);
        if (score.textScore > best.textScore) best = score;
      }
    }
    return best;
  }

  _TextScore _scoreFragment(String fragment, String candidateName, String explicitRoadType) {
    final candidateTokens = TextNormalizer.significantTokens(candidateName);
    final fragmentTokens = TextNormalizer.significantTokens(fragment);
    if (candidateTokens.isEmpty || fragmentTokens.isEmpty) {
      return const _TextScore.zero();
    }

    final ocrTypes = TextNormalizer.roadTypes(fragment);
    final candidateTypes = <String>{
      ...TextNormalizer.roadTypes(candidateName),
      ...TextNormalizer.roadTypes(explicitRoadType),
    };
    final roadTypeCompatible = ocrTypes.isEmpty ||
        candidateTypes.isEmpty ||
        ocrTypes.intersection(candidateTypes).isNotEmpty;

    var weightedMatches = 0.0;
    var totalWeight = 0.0;
    var weakestMatch = 1.0;
    for (final candidateToken in candidateTokens) {
      final weight = math.max(2.0, candidateToken.length.toDouble());
      totalWeight += weight;
      var bestToken = 0.0;
      for (final ocrToken in fragmentTokens) {
        bestToken = math.max(bestToken, _tokenSimilarity(candidateToken, ocrToken));
      }
      weakestMatch = math.min(weakestMatch, bestToken);
      weightedMatches += bestToken * weight;
    }
    final coverage = totalWeight == 0 ? 0.0 : weightedMatches / totalWeight;

    final candidatePhrase = candidateTokens.join(' ');
    final phraseScore = _bestWindowSimilarity(candidatePhrase, fragmentTokens, candidateTokens.length);
    final fragmentSignificant = fragmentTokens.join(' ');
    final containsWholeName = fragmentSignificant.contains(candidatePhrase);

    var textScore = containsWholeName
        ? 1.0
        : (coverage * 0.68 + phraseScore * 0.32);

    // Pour les noms à un seul mot, on exige une quasi-correspondance exacte.
    if (candidateTokens.length == 1 && weakestMatch < 0.86) {
      textScore *= 0.55;
    }
    // Pour les noms composés, un mot totalement absent doit coûter cher.
    if (candidateTokens.length >= 2 && weakestMatch < 0.58) {
      textScore *= 0.55;
    }
    if (!roadTypeCompatible) textScore *= 0.72;

    return _TextScore(
      textScore: textScore.clamp(0.0, 1.0).toDouble(),
      coverage: coverage.clamp(0.0, 1.0).toDouble(),
      phraseScore: phraseScore.clamp(0.0, 1.0).toDouble(),
      fragment: fragment,
      roadTypeCompatible: roadTypeCompatible,
    );
  }

  double _bestWindowSimilarity(String candidate, List<String> tokens, int candidateLength) {
    var best = 0.0;
    final minimum = math.max(1, candidateLength - 1);
    final maximum = math.min(tokens.length, candidateLength + 1);
    for (var windowLength = minimum; windowLength <= maximum; windowLength++) {
      for (var start = 0; start + windowLength <= tokens.length; start++) {
        final window = tokens.sublist(start, start + windowLength).join(' ');
        best = math.max(best, _stringSimilarity(candidate, window));
      }
    }
    return best;
  }

  double _tokenSimilarity(String first, String second) {
    if (first == second) return 1.0;
    if (first.length <= 3 || second.length <= 3) return 0.0;
    return _stringSimilarity(first, second);
  }

  double _stringSimilarity(String first, String second) {
    if (first.isEmpty || second.isEmpty) return 0;
    if (first == second) return 1;
    final longest = math.max(first.length, second.length);
    return (1 - _levenshtein(first, second) / longest).clamp(0.0, 1.0).toDouble();
  }

  int _levenshtein(String first, String second) {
    final previous = List<int>.generate(second.length + 1, (index) => index);
    final current = List<int>.filled(second.length + 1, 0);
    for (var i = 1; i <= first.length; i++) {
      current[0] = i;
      for (var j = 1; j <= second.length; j++) {
        final substitutionCost = first.codeUnitAt(i - 1) == second.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + substitutionCost,
        );
      }
      for (var j = 0; j <= second.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[second.length];
  }
}

class _TextScore {
  const _TextScore({
    required this.textScore,
    required this.coverage,
    required this.phraseScore,
    required this.fragment,
    required this.roadTypeCompatible,
  });

  const _TextScore.zero()
      : textScore = 0,
        coverage = 0,
        phraseScore = 0,
        fragment = '',
        roadTypeCompatible = true;

  final double textScore;
  final double coverage;
  final double phraseScore;
  final String fragment;
  final bool roadTypeCompatible;
}
