import 'package:flutter_test/flutter_test.dart';
import 'package:ruedex_mvp/services/text_normalizer.dart';

void main() {
  group('TextNormalizer', () {
    test('retire les accents et uniformise les types de voie', () {
      expect(
        TextNormalizer.normalize('Bd Georges-Méliès'),
        'BOULEVARD GEORGES MELIES',
      );
    });

    test('corrige certaines confusions OCR entre lettres et chiffres', () {
      expect(
        TextNormalizer.normalize('RUE VICT0R HUG0'),
        'RUE VICTOR HUGO',
      );
    });
  });
}
