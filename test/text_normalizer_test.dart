import 'package:flutter_test/flutter_test.dart';
import 'package:ruedex_mvp/services/text_normalizer.dart';

void main() {
  test('corrige les erreurs OCR fréquentes', () {
    expect(TextNormalizer.normalize('RUE VICT0R HUG0'), 'RUE VICTOR HUGO');
  });

  test('retire les types de voie du nom significatif', () {
    expect(TextNormalizer.significantName('Rue René-Boulanger'), 'RENE BOULANGER');
    expect(TextNormalizer.significantName('Avenue de la République'), 'REPUBLIQUE');
  });

  test('rue seule ne contient aucun nom significatif', () {
    expect(TextNormalizer.significantTokens('RUE'), isEmpty);
  });
}
