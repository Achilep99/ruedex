import 'street_entry.dart';

class MatchCandidate {
  const MatchCandidate({
    required this.street,
    required this.textScore,
    required this.locationScore,
    required this.finalScore,
    required this.distanceMeters,
    required this.matchedFragment,
  });

  final StreetEntry street;
  final double textScore;
  final double locationScore;
  final double finalScore;
  final double? distanceMeters;
  final String matchedFragment;

  int get percentage => (finalScore * 100).round().clamp(0, 100).toInt();
  int get textPercentage => (textScore * 100).round().clamp(0, 100).toInt();
}
