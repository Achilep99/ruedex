import 'street_entry.dart';

class MatchCandidate {
  const MatchCandidate({
    required this.street,
    required this.textScore,
    required this.tokenCoverage,
    required this.phraseScore,
    required this.locationScore,
    required this.finalScore,
    required this.distanceMeters,
    required this.matchedFragment,
    required this.roadTypeCompatible,
  });

  final StreetEntry street;
  final double textScore;
  final double tokenCoverage;
  final double phraseScore;
  final double locationScore;
  final double finalScore;
  final double? distanceMeters;
  final String matchedFragment;
  final bool roadTypeCompatible;

  int get percentage => (finalScore * 100).round().clamp(0, 100).toInt();
  int get textPercentage => (textScore * 100).round().clamp(0, 100).toInt();
  int get coveragePercentage => (tokenCoverage * 100).round().clamp(0, 100).toInt();
}

class MatchDecision {
  const MatchDecision({
    required this.accepted,
    required this.best,
    required this.reason,
    required this.margin,
  });

  final bool accepted;
  final MatchCandidate? best;
  final String reason;
  final double margin;
}
