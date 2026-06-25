import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../models/match_candidate.dart';
import '../models/street_entry.dart';
import 'text_normalizer.dart';

class StreetMatcher {
  const StreetMatcher({
    this.maximumGpsDistanceMeters = 750,
    this.validationThreshold = 0.72,
  });

  final double maximumGpsDistanceMeters;
  final double validationThreshold;

  List<MatchCandidate> findCandidates({
    required String recognizedText,
    required List<StreetEntry> streets,
    double? latitude,
    double? longitude,
    int maximumResults = 5,
  }) {
    final fragments = TextNormalizer.fragments(recognizedText);
    if (fragments.isEmpty) {
      return const [];
    }

    final candidates = <MatchCandidate>[];

    for (final street in streets) {
      final distance = latitude == null || longitude == null
          ? null
          : Geolocator.distanceBetween(
              latitude,
              longitude,
              street.latitude,
              street.longitude,
            );

      if (distance != null && distance > maximumGpsDistanceMeters * 4) {
        continue;
      }

      var bestTextScore = 0.0;
      var bestFragment = '';

      for (final fragment in fragments) {
        for (final possibleName in street.allNames) {
          final score = _textSimilarity(
            fragment,
            TextNormalizer.normalize(possibleName),
          );
          if (score > bestTextScore) {
            bestTextScore = score;
            bestFragment = fragment;
          }
        }
      }

      final locationScore = distance == null
          ? 0.5
          : math.max(0.0, 1 - (distance / maximumGpsDistanceMeters));

      final finalScore = distance == null
          ? bestTextScore
          : (bestTextScore * 0.80) + (locationScore * 0.20);

      candidates.add(
        MatchCandidate(
          street: street,
          textScore: bestTextScore,
          locationScore: locationScore,
          finalScore: finalScore,
          distanceMeters: distance,
          matchedFragment: bestFragment,
        ),
      );
    }

    candidates.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return candidates.take(maximumResults).toList(growable: false);
  }

  bool canValidate(MatchCandidate candidate) {
    return candidate.finalScore >= validationThreshold &&
        candidate.textScore >= 0.67;
  }

  double _textSimilarity(String first, String second) {
    if (first.isEmpty || second.isEmpty) {
      return 0;
    }
    if (first == second) {
      return 1;
    }
    if (first.contains(second) || second.contains(first)) {
      final shortest = math.min(first.length, second.length);
      final longest = math.max(first.length, second.length);
      return 0.86 + (0.14 * shortest / longest);
    }

    final editScore = 1 - (_levenshtein(first, second) / math.max(first.length, second.length));
    final tokenScore = _tokenScore(first, second);
    return (editScore * 0.65) + (tokenScore * 0.35);
  }

  double _tokenScore(String first, String second) {
    final firstTokens = first.split(' ').where((token) => token.length > 1).toSet();
    final secondTokens = second.split(' ').where((token) => token.length > 1).toSet();
    if (firstTokens.isEmpty || secondTokens.isEmpty) {
      return 0;
    }

    final intersection = firstTokens.intersection(secondTokens).length;
    final union = firstTokens.union(secondTokens).length;
    return intersection / union;
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
