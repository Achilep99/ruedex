class PlateCheckResult {
  const PlateCheckResult({
    required this.score,
    required this.isProbablePlate,
    required this.diagnostics,
  });

  final double score;
  final bool isProbablePlate;
  final List<String> diagnostics;

  int get percentage => (score * 100).round().clamp(0, 100).toInt();
}
