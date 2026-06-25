import 'geo_point.dart';

class StreetEntry {
  StreetEntry({
    required this.id,
    required this.officialName,
    required this.roadType,
    required this.normalizedName,
    required this.aliases,
    required this.city,
    required this.arrondissement,
    required this.origin,
    required this.rarity,
    required this.raritySource,
    required this.segments,
  }) : bounds = GeoBounds.fromPoints(segments.expand((segment) => segment));

  final String id;
  final String officialName;
  final String roadType;
  final String normalizedName;
  final List<String> aliases;
  final String city;
  final String arrondissement;
  final String origin;
  final StreetRarity rarity;
  final String raritySource;
  final List<List<GeoPoint>> segments;
  final GeoBounds bounds;

  factory StreetEntry.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    return StreetEntry(
      id: json['id'] as String,
      officialName: json['officialName'] as String,
      roadType: json['roadType'] as String? ?? '',
      normalizedName: json['normalizedName'] as String? ?? '',
      aliases: (json['aliases'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(growable: false),
      city: json['city'] as String? ?? 'Paris',
      arrondissement: json['arrondissement'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      rarity: StreetRarity.fromJson(json['rarity'] as String? ?? 'nonClassee'),
      raritySource: json['raritySource'] as String? ?? 'non_classee',
      segments: rawSegments
          .map(
            (segment) => (segment as List<dynamic>)
                .map((point) => GeoPoint.fromJson(point as List<dynamic>))
                .toList(growable: false),
          )
          .where((segment) => segment.length >= 2)
          .toList(growable: false),
    );
  }

  Iterable<String> get allNames sync* {
    yield officialName;
    yield* aliases;
  }

  bool get hasVerifiedOrigin => origin.trim().isNotEmpty;

  GeoPoint get center {
    if (segments.isEmpty) {
      return const GeoPoint(48.8566, 2.3522);
    }
    var lat = 0.0;
    var lon = 0.0;
    var count = 0;
    for (final point in segments.expand((segment) => segment)) {
      lat += point.latitude;
      lon += point.longitude;
      count++;
    }
    return GeoPoint(lat / count, lon / count);
  }
}

enum StreetRarity {
  nonClassee('Non classée', 0),
  commune('Commune', 1),
  peuCommune('Peu commune', 2),
  rare('Rare', 3),
  epique('Épique', 4),
  legendaire('Légendaire', 5);

  const StreetRarity(this.label, this.stars);

  final String label;
  final int stars;

  static StreetRarity fromJson(String value) {
    return StreetRarity.values.firstWhere(
      (rarity) => rarity.name == value,
      orElse: () => StreetRarity.nonClassee,
    );
  }
}
