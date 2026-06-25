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
    'R': 'RUE',
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
    'CHE': 'CHEMIN',
    'CH': 'CHEMIN',
    'RTE': 'ROUTE',
    'SQ': 'SQUARE',
  };

  static const Set<String> streetTypeWords = {
    'RUE',
    'AVENUE',
    'BOULEVARD',
    'PLACE',
    'IMPASSE',
    'CHEMIN',
    'ROUTE',
    'QUAI',
    'ALLEE',
    'PASSAGE',
    'SQUARE',
    'CITE',
    'VILLA',
    'COUR',
    'ROND POINT',
    'PROMENADE',
    'SENTIER',
    'TERRASSE',
    'PORT',
    'PONT',
  };

  static const Set<String> connectorWords = {
    'DE', 'DU', 'DES', 'LA', 'LE', 'LES', 'D', 'L', 'AU', 'AUX', 'A', 'ET',
  };

  static const Set<String> _noiseWords = {
    'VILLE',
    'MAIRIE',
    'COMMUNE',
    'ARRONDISSEMENT',
    'PARIS',
    'FRANCE',
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

    return text
        .split(' ')
        .where((token) => token.isNotEmpty)
        .map((token) => _streetTypeAliases[token] ?? token)
        .join(' ');
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
      if (character == '5') characters[index] = 'S';
      if (character == '8') characters[index] = 'B';
    }
    return characters.join();
  }

  static Set<String> roadTypes(String input) {
    final normalized = normalize(input);
    final types = <String>{};
    for (final type in streetTypeWords) {
      if (normalized == type || normalized.contains('$type ')) {
        types.add(type);
      }
    }
    return types;
  }

  static List<String> significantTokens(String input) {
    return normalize(input)
        .split(' ')
        .where(
          (token) =>
              token.length >= 2 &&
              !streetTypeWords.contains(token) &&
              !connectorWords.contains(token) &&
              !_noiseWords.contains(token),
        )
        .toList(growable: false);
  }

  static String significantName(String input) => significantTokens(input).join(' ');

  static List<String> fragments(String rawText) {
    final normalizedLines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map(normalize)
        .where((line) => line.length >= 3)
        .toList(growable: false);

    final fragments = <String>{};
    fragments.addAll(normalizedLines);
    final whole = normalize(rawText);
    if (whole.isNotEmpty) fragments.add(whole);

    for (var index = 0; index < normalizedLines.length - 1; index++) {
      fragments.add('${normalizedLines[index]} ${normalizedLines[index + 1]}');
    }

    return fragments
        .where((fragment) => significantTokens(fragment).isNotEmpty)
        .toList(growable: false);
  }
}
