import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/geo_point.dart';
import '../models/street_database.dart';
import '../models/street_entry.dart';

class StreetRepository {
  Future<StreetDatabase> loadDatabase() async {
    final raw = await rootBundle.loadString('assets/data/paris_streets.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final streets = (json['streets'] as List<dynamic>? ?? const [])
        .map((item) => StreetEntry.fromJson(item as Map<String, dynamic>))
        .where((street) => street.segments.isNotEmpty)
        .toList(growable: false);

    final metadata = json['metadata'] as Map<String, dynamic>? ?? const {};
    final rawBounds = metadata['bounds'] as Map<String, dynamic>?;
    final bounds = rawBounds == null
        ? GeoBounds.fromPoints(
            streets.expand((street) => street.segments.expand((segment) => segment)),
          ).padded(0.003, 0.004)
        : GeoBounds(
            minLatitude: (rawBounds['minLatitude'] as num).toDouble(),
            maxLatitude: (rawBounds['maxLatitude'] as num).toDouble(),
            minLongitude: (rawBounds['minLongitude'] as num).toDouble(),
            maxLongitude: (rawBounds['maxLongitude'] as num).toDouble(),
          );

    return StreetDatabase(
      streets: streets,
      bounds: bounds,
      sourceLabel: metadata['sourceLabel'] as String? ?? 'Ville de Paris — ODbL',
      generatedAt: metadata['generatedAt'] as String? ?? '',
    );
  }
}
