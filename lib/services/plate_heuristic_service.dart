import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/ocr_scan_result.dart';
import '../models/plate_check_result.dart';
import 'text_normalizer.dart';

/// Filtre visuel provisoire avant le futur détecteur entraîné.
///
/// Le service ne suppose plus que la plaque remplit un cadre horizontal fixe.
/// Il cherche plusieurs groupes de lignes OCR dans toute l'image, puis retient
/// la zone qui ressemble le plus à une plaque : texte regroupé, zone lisible,
/// contraste, fond distinct et éventuelles traces de contour.
class PlateHeuristicService {
  const PlateHeuristicService();

  Future<PlateCheckResult> analyze(String imagePath, OcrScanResult ocr) async {
    final bytes = await File(imagePath).readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const PlateCheckResult(
        score: 0,
        isProbablePlate: false,
        diagnostics: ['Image illisible.'],
      );
    }

    decoded = img.bakeOrientation(decoded);
    final originalWidth = decoded.width.toDouble();
    final originalHeight = decoded.height.toDouble();

    if (decoded.width > 720) {
      decoded = img.copyResize(decoded, width: 720);
    }

    final regions = _candidateRegions(
      ocr.lines,
      originalWidth,
      originalHeight,
    );
    if (regions.isEmpty) {
      return const PlateCheckResult(
        score: 0,
        isProbablePlate: false,
        diagnostics: [
          'Aucun groupe de texte pouvant correspondre à un nom de rue.',
        ],
      );
    }

    _CandidateEvaluation? best;
    for (final region in regions) {
      final evaluation = _evaluateRegion(
        decoded,
        region,
        originalWidth,
        originalHeight,
      );
      if (best == null || evaluation.score > best.score) {
        best = evaluation;
      }
    }

    final selected = best!;
    final diagnostics = <String>[
      'Zone retenue : « ${selected.text.replaceAll('\n', ' / ')} ».',
      'Format de la zone : ${(selected.geometryScore * 100).round()} %.',
      'Contour ou séparation visuelle : ${(selected.frameScore * 100).round()} %.',
      'Fond cohérent : ${(selected.backgroundScore * 100).round()} %.',
      'Contraste local : ${(selected.contrastScore * 100).round()} %.',
      'Netteté locale : ${(selected.sharpnessScore * 100).round()} %.',
    ];

    if (!selected.hasStreetType) {
      diagnostics.add(
        'Type de voie non lu : accepté seulement avec un nom et un GPS très fiables.',
      );
    }
    if (regions.length > 1) {
      diagnostics.add('${regions.length} zones de texte comparées dans l’image.');
    }

    return PlateCheckResult(
      score: selected.score.clamp(0.0, 1.0).toDouble(),
      isProbablePlate: selected.isProbablePlate,
      diagnostics: diagnostics,
    );
  }

  List<_TextRegion> _candidateRegions(
    List<OcrLineResult> lines,
    double imageWidth,
    double imageHeight,
  ) {
    final eligible = lines.where((line) {
      return TextNormalizer.significantTokens(line.text).isNotEmpty ||
          TextNormalizer.roadTypes(line.text).isNotEmpty;
    }).toList(growable: false);

    if (eligible.isEmpty) {
      return const [];
    }

    final regions = <_TextRegion>[];
    final keys = <String>{};

    void addRegion(List<OcrLineResult> regionLines) {
      if (regionLines.isEmpty) {
        return;
      }
      final sorted = [...regionLines]
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      var bounds = sorted.first.boundingBox;
      for (final line in sorted.skip(1)) {
        bounds = bounds.expandToInclude(line.boundingBox);
      }

      final areaRatio = bounds.width * bounds.height /
          math.max(1.0, imageWidth * imageHeight);
      if (areaRatio < 0.00025 || areaRatio > 0.88) {
        return;
      }

      final text = sorted.map((line) => line.text).join('\n').trim();
      if (TextNormalizer.significantTokens(text).isEmpty) {
        return;
      }

      final key = '${bounds.left.round()}:${bounds.top.round()}:'
          '${bounds.right.round()}:${bounds.bottom.round()}:'
          '${TextNormalizer.normalize(text)}';
      if (keys.add(key)) {
        regions.add(_TextRegion(text: text, bounds: bounds, lines: sorted));
      }
    }

    for (final anchor in eligible) {
      addRegion([anchor]);

      final related = eligible.where((other) {
        return _linesBelongTogether(anchor.boundingBox, other.boundingBox);
      }).toList();

      related.sort((a, b) {
        final first = _normalizedCenterDistance(
          anchor.boundingBox,
          a.boundingBox,
        );
        final second = _normalizedCenterDistance(
          anchor.boundingBox,
          b.boundingBox,
        );
        return first.compareTo(second);
      });

      addRegion(related.take(5).toList(growable: false));
    }

    return regions;
  }

  bool _linesBelongTogether(Rect first, Rect second) {
    if (first == second) {
      return true;
    }

    final maxHeight = math.max(first.height, second.height);
    final maxWidth = math.max(first.width, second.width);
    final centerDx = (first.center.dx - second.center.dx).abs();
    final centerDy = (first.center.dy - second.center.dy).abs();

    final overlap = math.max(
      0.0,
      math.min(first.right, second.right) -
          math.max(first.left, second.left),
    );
    final minimumWidth = math.max(1.0, math.min(first.width, second.width));
    final overlapRatio = overlap / minimumWidth;

    final verticallyClose = centerDy <= maxHeight * 5.5;
    final horizontallyRelated = overlapRatio >= 0.12 ||
        centerDx <= maxWidth * 0.55 + maxHeight * 1.5;
    return verticallyClose && horizontallyRelated;
  }

  double _normalizedCenterDistance(Rect first, Rect second) {
    final reference = math.max(1.0, math.max(first.height, second.height));
    final dx = (first.center.dx - second.center.dx).abs() / reference;
    final dy = (first.center.dy - second.center.dy).abs() / reference;
    return dx * 0.55 + dy;
  }

  _CandidateEvaluation _evaluateRegion(
    img.Image image,
    _TextRegion region,
    double originalWidth,
    double originalHeight,
  ) {
    final bounds = region.bounds;
    final aspect = bounds.width / math.max(1.0, bounds.height);
    final areaRatio = bounds.width * bounds.height /
        math.max(1.0, originalWidth * originalHeight);

    final aspectScore = _rangeScore(
      aspect,
      idealMinimum: 0.55,
      idealMaximum: 9.0,
      acceptedMinimum: 0.30,
      acceptedMaximum: 13.0,
    );
    final areaScore = _rangeScore(
      areaRatio,
      idealMinimum: 0.0012,
      idealMaximum: 0.62,
      acceptedMinimum: 0.00025,
      acceptedMaximum: 0.85,
    );
    final lineCount = region.lines.length;
    final lineScore = lineCount <= 5 ? 1.0 : 0.45;
    final geometryScore =
        aspectScore * 0.48 + areaScore * 0.32 + lineScore * 0.20;

    final tokens = TextNormalizer.significantTokens(region.text);
    final tokenCharacters = tokens.fold<int>(
      0,
      (total, token) => total + token.length,
    );
    final hasStreetType = TextNormalizer.roadTypes(region.text).isNotEmpty;
    final contentScore = tokens.isEmpty
        ? 0.0
        : (0.42 +
                math.min(0.40, tokenCharacters / 30.0) +
                (hasStreetType ? 0.18 : 0.06))
            .clamp(0.0, 1.0)
            .toDouble();

    final scaleX = image.width / originalWidth;
    final scaleY = image.height / originalHeight;
    final scaledBounds = Rect.fromLTRB(
      bounds.left * scaleX,
      bounds.top * scaleY,
      bounds.right * scaleX,
      bounds.bottom * scaleY,
    );
    final candidateBounds = _expandedPlateBounds(
      scaledBounds,
      image.width,
      image.height,
    );

    final evidence = _plateSurfaceEvidence(image, candidateBounds);
    final localQuality = _imageQuality(_crop(image, candidateBounds));
    final contrastScore =
        ((localQuality.contrast - 10) / 38).clamp(0.0, 1.0).toDouble();
    final sharpnessScore =
        ((localQuality.edgeEnergy - 3.5) / 24).clamp(0.0, 1.0).toDouble();

    final score = contentScore * 0.29 +
        geometryScore * 0.20 +
        contrastScore * 0.16 +
        sharpnessScore * 0.14 +
        evidence.frameScore * 0.11 +
        evidence.backgroundUniformity * 0.10;

    final hasVisualEvidence = evidence.frameScore >= 0.12 ||
        evidence.backgroundUniformity >= 0.24 ||
        contrastScore >= 0.24;
    final probable = score >= 0.46 &&
        contentScore >= 0.60 &&
        sharpnessScore >= 0.08 &&
        hasVisualEvidence;

    return _CandidateEvaluation(
      text: region.text,
      score: score,
      isProbablePlate: probable,
      geometryScore: geometryScore,
      frameScore: evidence.frameScore,
      backgroundScore: evidence.backgroundUniformity,
      contrastScore: contrastScore,
      sharpnessScore: sharpnessScore,
      hasStreetType: hasStreetType,
    );
  }

  double _rangeScore(
    double value, {
    required double idealMinimum,
    required double idealMaximum,
    required double acceptedMinimum,
    required double acceptedMaximum,
  }) {
    if (value >= idealMinimum && value <= idealMaximum) {
      return 1.0;
    }
    if (value < acceptedMinimum || value > acceptedMaximum) {
      return 0.15;
    }
    if (value < idealMinimum) {
      return 0.35 +
          0.65 *
              (value - acceptedMinimum) /
              math.max(0.000001, idealMinimum - acceptedMinimum);
    }
    return 0.35 +
        0.65 *
            (acceptedMaximum - value) /
            math.max(0.000001, acceptedMaximum - idealMaximum);
  }

  Rect _expandedPlateBounds(Rect text, int width, int height) {
    final horizontalPadding = math.max(12.0, text.width * 0.28);
    final verticalPadding = math.max(10.0, text.height * 0.48);
    return Rect.fromLTRB(
      (text.left - horizontalPadding).clamp(1.0, width - 2.0).toDouble(),
      (text.top - verticalPadding).clamp(1.0, height - 2.0).toDouble(),
      (text.right + horizontalPadding).clamp(2.0, width - 1.0).toDouble(),
      (text.bottom + verticalPadding).clamp(2.0, height - 1.0).toDouble(),
    );
  }

  img.Image _crop(img.Image image, Rect rect) {
    final left = rect.left.floor().clamp(0, image.width - 1).toInt();
    final top = rect.top.floor().clamp(0, image.height - 1).toInt();
    final right = rect.right.ceil().clamp(left + 1, image.width).toInt();
    final bottom = rect.bottom.ceil().clamp(top + 1, image.height).toInt();
    return img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  _PlateSurfaceEvidence _plateSurfaceEvidence(img.Image image, Rect rect) {
    if (rect.width < 18 || rect.height < 12) {
      return const _PlateSurfaceEvidence(
        frameScore: 0,
        backgroundUniformity: 0,
      );
    }

    const sampleCount = 32;
    const offset = 3;
    final sideStrengths = <double>[];

    double horizontalSide(double y, double insideY, double outsideY) {
      var sum = 0.0;
      for (var index = 0; index < sampleCount; index++) {
        final x = rect.left + rect.width * (index + 0.5) / sampleCount;
        final edge = _luminance(image, x.round(), y.round());
        final inside = _luminance(image, x.round(), insideY.round());
        final outside = _luminance(image, x.round(), outsideY.round());
        sum += math.max((edge - inside).abs(), (inside - outside).abs());
      }
      return sum / sampleCount;
    }

    double verticalSide(double x, double insideX, double outsideX) {
      var sum = 0.0;
      for (var index = 0; index < sampleCount; index++) {
        final y = rect.top + rect.height * (index + 0.5) / sampleCount;
        final edge = _luminance(image, x.round(), y.round());
        final inside = _luminance(image, insideX.round(), y.round());
        final outside = _luminance(image, outsideX.round(), y.round());
        sum += math.max((edge - inside).abs(), (inside - outside).abs());
      }
      return sum / sampleCount;
    }

    sideStrengths.add(
      horizontalSide(rect.top, rect.top + offset, rect.top - offset),
    );
    sideStrengths.add(
      horizontalSide(rect.bottom, rect.bottom - offset, rect.bottom + offset),
    );
    sideStrengths.add(
      verticalSide(rect.left, rect.left + offset, rect.left - offset),
    );
    sideStrengths.add(
      verticalSide(rect.right, rect.right - offset, rect.right + offset),
    );

    final averageEdge =
        sideStrengths.reduce((first, second) => first + second) /
            sideStrengths.length;
    final strongSides = sideStrengths.where((strength) => strength >= 7).length;
    final edgeScore = ((averageEdge - 2.5) / 22).clamp(0.0, 1.0).toDouble();
    final coverageScore = strongSides / 4.0;
    final frameScore = edgeScore * 0.62 + coverageScore * 0.38;

    final colors = <_Rgb>[];
    const gridX = 12;
    const gridY = 8;
    for (var row = 0; row < gridY; row++) {
      for (var column = 0; column < gridX; column++) {
        if (row >= 2 && row <= 5 && column >= 2 && column <= 9) {
          continue;
        }
        final x = rect.left + rect.width * (column + 0.5) / gridX;
        final y = rect.top + rect.height * (row + 0.5) / gridY;
        colors.add(_rgb(image, x.round(), y.round()));
      }
    }

    return _PlateSurfaceEvidence(
      frameScore: frameScore.clamp(0.0, 1.0).toDouble(),
      backgroundUniformity: _colorUniformity(colors),
    );
  }

  double _colorUniformity(List<_Rgb> colors) {
    if (colors.isEmpty) {
      return 0;
    }
    final meanR =
        colors.fold<double>(0, (sum, color) => sum + color.r) / colors.length;
    final meanG =
        colors.fold<double>(0, (sum, color) => sum + color.g) / colors.length;
    final meanB =
        colors.fold<double>(0, (sum, color) => sum + color.b) / colors.length;

    var variance = 0.0;
    for (final color in colors) {
      variance += math.pow(color.r - meanR, 2).toDouble();
      variance += math.pow(color.g - meanG, 2).toDouble();
      variance += math.pow(color.b - meanB, 2).toDouble();
    }
    final deviation = math.sqrt(variance / (colors.length * 3));
    return (1 - deviation / 78).clamp(0.0, 1.0).toDouble();
  }

  _Rgb _rgb(img.Image image, int x, int y) {
    final safeX = x.clamp(0, image.width - 1).toInt();
    final safeY = y.clamp(0, image.height - 1).toInt();
    final pixel = image.getPixel(safeX, safeY);
    return _Rgb(
      pixel.r.toDouble(),
      pixel.g.toDouble(),
      pixel.b.toDouble(),
    );
  }

  double _luminance(img.Image image, int x, int y) {
    final color = _rgb(image, x, y);
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }

  _ImageQuality _imageQuality(img.Image image) {
    final step = math.max(1, math.min(image.width, image.height) ~/ 150);
    var count = 0;
    var sum = 0.0;
    var sumSquares = 0.0;
    var edgeSum = 0.0;

    for (var y = 0; y < image.height - step; y += step) {
      for (var x = 0; x < image.width - step; x += step) {
        final value = _luminance(image, x, y);
        sum += value;
        sumSquares += value * value;
        edgeSum += (value - _luminance(image, x + step, y)).abs();
        edgeSum += (value - _luminance(image, x, y + step)).abs();
        count++;
      }
    }

    if (count == 0) {
      return const _ImageQuality(contrast: 0, edgeEnergy: 0);
    }
    final mean = sum / count;
    final variance = math.max(0.0, sumSquares / count - mean * mean);
    return _ImageQuality(
      contrast: math.sqrt(variance),
      edgeEnergy: edgeSum / (count * 2),
    );
  }
}

class _TextRegion {
  const _TextRegion({
    required this.text,
    required this.bounds,
    required this.lines,
  });

  final String text;
  final Rect bounds;
  final List<OcrLineResult> lines;
}

class _CandidateEvaluation {
  const _CandidateEvaluation({
    required this.text,
    required this.score,
    required this.isProbablePlate,
    required this.geometryScore,
    required this.frameScore,
    required this.backgroundScore,
    required this.contrastScore,
    required this.sharpnessScore,
    required this.hasStreetType,
  });

  final String text;
  final double score;
  final bool isProbablePlate;
  final double geometryScore;
  final double frameScore;
  final double backgroundScore;
  final double contrastScore;
  final double sharpnessScore;
  final bool hasStreetType;
}

class _ImageQuality {
  const _ImageQuality({required this.contrast, required this.edgeEnergy});

  final double contrast;
  final double edgeEnergy;
}

class _PlateSurfaceEvidence {
  const _PlateSurfaceEvidence({
    required this.frameScore,
    required this.backgroundUniformity,
  });

  final double frameScore;
  final double backgroundUniformity;
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;
}
