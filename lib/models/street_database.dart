import 'geo_point.dart';
import 'street_entry.dart';

class StreetDatabase {
  const StreetDatabase({
    required this.streets,
    required this.bounds,
    required this.sourceLabel,
    required this.generatedAt,
  });

  final List<StreetEntry> streets;
  final GeoBounds bounds;
  final String sourceLabel;
  final String generatedAt;
}
