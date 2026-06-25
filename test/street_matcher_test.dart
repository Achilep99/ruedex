import 'package:flutter_test/flutter_test.dart';
import 'package:ruedex_mvp/models/street_entry.dart';
import 'package:ruedex_mvp/services/street_matcher.dart';

void main() {
  const victorHugo = StreetEntry(
    id: 'victor_hugo',
    officialName: 'Avenue Victor-Hugo',
    aliases: ['Rue Victor Hugo', 'Victor Hugo'],
    city: 'Paris',
    latitude: 48.8706,
    longitude: 2.2854,
    subjectName: 'Victor Hugo',
    summary: 'Écrivain français.',
    rarity: StreetRarity.commune,
  );

  const pasteur = StreetEntry(
    id: 'pasteur',
    officialName: 'Boulevard Pasteur',
    aliases: ['Pasteur'],
    city: 'Paris',
    latitude: 48.8427,
    longitude: 2.3147,
    subjectName: 'Louis Pasteur',
    summary: 'Scientifique français.',
    rarity: StreetRarity.commune,
  );

  test('retrouve Victor Hugo malgré les erreurs OCR', () {
    const matcher = StreetMatcher();
    final candidates = matcher.findCandidates(
      recognizedText: 'PARIS 16e\nRUE VICT0R HUG0',
      streets: const [pasteur, victorHugo],
      latitude: 48.8706,
      longitude: 2.2854,
    );

    expect(candidates.first.street.id, 'victor_hugo');
    expect(matcher.canValidate(candidates.first), isTrue);
  });
}
