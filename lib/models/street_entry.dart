class StreetEntry {
  const StreetEntry({
    required this.id,
    required this.officialName,
    required this.aliases,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.subjectName,
    required this.summary,
    required this.rarity,
  });

  final String id;
  final String officialName;
  final List<String> aliases;
  final String city;
  final double latitude;
  final double longitude;
  final String subjectName;
  final String summary;
  final StreetRarity rarity;

  factory StreetEntry.fromJson(Map<String, dynamic> json) {
    return StreetEntry(
      id: json['id'] as String,
      officialName: json['officialName'] as String,
      aliases: (json['aliases'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(growable: false),
      city: json['city'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      subjectName: json['subjectName'] as String,
      summary: json['summary'] as String,
      rarity: StreetRarity.fromJson(json['rarity'] as String),
    );
  }

  Iterable<String> get allNames sync* {
    yield officialName;
    yield* aliases;
  }
}

enum StreetRarity {
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
      orElse: () => StreetRarity.commune,
    );
  }
}
