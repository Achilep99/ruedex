class TextNormalizer {
  static const Map<String, String> _accentMap = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'Ç': 'C',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'Ñ': 'N',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'Ý': 'Y', 'Ÿ': 'Y',
    'Œ': 'OE', 'Æ': 'AE',
  };

  static const Map<String, String> _streetTypeAliases = {
    'AV': 'AVENUE',
    'AVE': 'AVENUE',
    'AVEN': 'AVENUE',
    'BD': 'BOULEVARD',
    'BLD': 'BOULEVARD',
    'BOUL': 'BOULEVARD',
    'PL': 'PLACE',
    'PLCE': 'PLACE',
    'IMP': 'IMPASSE',
    'ALL': 'ALLEE',
    'ALLÉE': 'ALLEE',
    'CHE': 'CHEMIN',
    'CH': 'CHEMIN',
  };

  static String normalize(String input, {bool correctOcrDigits = true}) {
    var text = input.toUpperCase();

    _accentMap.forEach((accented, plain) {
      text = text.replaceAll(accented, plain);
    });

    if (correctOcrDigits) {
      text = _correctOcrDigits(text);
    }

    text = text
        .replaceAll(RegExp(r"[^A-Z0-9 '\-]"), ' ')
        .replaceAll(RegExp(r"[-']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final tokens = text.split(' ').where((token) => token.isNotEmpty).map(
      (token) => _streetTypeAliases[token] ?? token,
    );

    return tokens.join(' ');
  }

  static String _correctOcrDigits(String input) {
    final characters = input.split('');

    bool isLetterAt(int index) {
      if (index < 0 || index >= characters.length) return false;
      return RegExp(r'[A-Z]').hasMatch(characters[index]);
    }

    for (var index = 0; index < characters.length; index++) {
      final character = characters[index];
      final touchesLetter = isLetterAt(index - 1) || isLetterAt(index + 1);
      if (!touchesLetter) continue;

      if (character == '0') characters[index] = 'O';
      if (character == '1') characters[index] = 'I';
    }

    return characters.join();
  }

  static String withoutNoiseWords(String input) {
    const noiseWords = {
      'VILLE',
      'MAIRIE',
      'COMMUNE',
      'ARRONDISSEMENT',
      'PARIS',
      'LYON',
      'MARSEILLE',
      'METROPOLE',
    };

    return normalize(input)
        .split(' ')
        .where((token) => !noiseWords.contains(token))
        .join(' ');
  }

  static List<String> fragments(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map(withoutNoiseWords)
        .where((line) => line.length >= 3)
        .toList(growable: false);

    final fragments = <String>{withoutNoiseWords(rawText)};
    fragments.addAll(lines);

    for (var index = 0; index < lines.length - 1; index++) {
      fragments.add('${lines[index]} ${lines[index + 1]}'.trim());
    }

    return fragments.where((fragment) => fragment.isNotEmpty).toList();
  }
}
