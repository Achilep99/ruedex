import 'package:flutter_test/flutter_test.dart';
import 'package:ruedex_mvp/models/geo_point.dart';
import 'package:ruedex_mvp/models/street_entry.dart';
import 'package:ruedex_mvp/services/street_matcher.dart';

StreetEntry street({
  required String id,
  required String name,
  required String type,
  required List<GeoPoint> points,
}) {
  return StreetEntry(
    id: id,
    officialName: name,
    roadType: type,
    normalizedName: name,
    aliases: const [],
    city: 'Paris',
    arrondissement: '',
    origin: '',
    rarity: StreetRarity.nonClassee,
    raritySource: 'test',
    segments: [points],
  );
}

void main() {
  const matcher = StreetMatcher();
  final streets = [
    street(
      id: 'rene',
      name: 'Rue René-Boulanger',
      type: 'RUE',
      points: const [GeoPoint(48.8690, 2.3590), GeoPoint(48.8690, 2.3610)],
    ),
    street(
      id: 'marie',
      name: 'Rue Marie-Stuart',
      type: 'RUE',
      points: const [GeoPoint(48.8692, 2.3593), GeoPoint(48.8692, 2.3613)],
    ),
  ];

  test('le mot RUE ne donne plus un gros match artificiel', () {
    final candidates = matcher.findCandidates(
      recognizedText: 'RUE RENE BOULANGER',
      streets: streets,
      latitude: 48.8690,
      longitude: 2.3600,
      gpsAccuracyMeters: 10,
    );
    expect(candidates.first.street.id, 'rene');
    final marie = candidates.where((candidate) => candidate.street.id == 'marie');
    expect(marie.isEmpty || marie.first.textScore < 0.35, isTrue);
  });

  test('une plaque ne contenant que RUE ne valide rien', () {
    final candidates = matcher.findCandidates(
      recognizedText: 'RUE',
      streets: streets,
      latitude: 48.8690,
      longitude: 2.3600,
      gpsAccuracyMeters: 10,
    );
    expect(candidates, isEmpty);
  });

  test('les erreurs OCR 0 vers O restent acceptées', () {
    final candidates = matcher.findCandidates(
      recognizedText: 'RUE RENE B0ULANGER',
      streets: streets,
      latitude: 48.8690,
      longitude: 2.3600,
      gpsAccuracyMeters: 10,
    );
    final decision = matcher.decide(candidates, gpsAccuracyMeters: 10);
    expect(decision.accepted, isTrue);
    expect(decision.best!.street.id, 'rene');
  });
}
