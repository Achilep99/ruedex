import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/ocr_scan_result.dart';
import '../models/plate_check_result.dart';
import 'text_normalizer.dart';

/// Filtre provisoire avant le futur détecteur entraîné.
///
/// Il ne prétend pas reconnaître une plaque avec certitude. Il vérifie que le
/// texte se trouve dans une zone plausible : forme allongée, contraste,
/// netteté, fond relativement homogène et traces de bord autour du texte.
class PlateHeuristicService {
  const PlateHeuristicService();

  Future<PlateCheckResult> analyze(String imagePath, OcrScanResult ocr) async {
    final diagnostics = <String>[];
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
    if (decoded.width > 640) {
      decoded = img.copyResize(decoded, width: 640);
    }

    final imageQuality = _imageQuality(decoded);
    final meaningfulLines = ocr.lines
        .where((line) => TextNormalizer.significantTokens(line.text).isNotEmpty)
        .toList(growable: false);

    Rect? textBounds;
    for (final line in meaningfulLines) {
      textBounds = textBounds == null
          ? line.boundingBox
          : textBounds.expandToInclude(line.boundingBox);
    }

    var geometryScore = 0.0;
    var frameScore = 0.0;
    var backgroundScore = 0.0;

    if (textBounds != null) {
      final aspect = textBounds.width / math.max(1.0, textBounds.height);
      final areaRatio = (textBounds.width * textBounds.height) /
          math.max(1.0, originalWidth * originalHeight);
      final aspectScore = aspect >= 1.35 && aspect <= 11.0 ? 1.0 : 0.25;
      final areaScore = areaRatio >= 0.008 && areaRatio <= 0.70 ? 1.0 : 0.30;
      final lineScore = meaningfulLines.length <= 5 ? 1.0 : 0.55;
      geometryScore =
          aspectScore * 0.50 + areaScore * 0.30 + lineScore * 0.20;

      final scaleX = decoded.width / originalWidth;
      final scaleY = decoded.height / originalHeight;
      final scaledTextBounds = Rect.fromLTRB(
        textBounds.left * scaleX,
        textBounds.top * scaleY,
        textBounds.right * scaleX,
        textBounds.bottom * scaleY,
      );
      final candidateBounds = _expandedPlateBounds(
        scaledTextBounds,
        decoded.width,
        decoded.height,
      );
      final evidence = _plateSurfaceEvidence(decoded, candidateBounds);
      frameScore = evidence.frameScore;
      backgroundScore = evidence.backgroundUniformity;

      diagnostics.add(
        'Zone texte : ratio ${aspect.toStringAsFixed(1)}, '
        '${(areaRatio * 100).toStringAsFixed(1)} % de l’image.',
      );
      diagnostics.add(
        'Bords rectangulaires probables : ${(frameScore * 100).round()} %.',
      );
      diagnostics.add(
        'Fond de plaque homogène : ${(backgroundScore * 100).round()} %.',
      );
    } else {
      diagnostics.add('Aucune zone de nom significative.');
    }

    final contentTokens = TextNormalizer.significantTokens(ocr.fullText);
    final hasStreetType = TextNormalizer.roadTypes(ocr.fullText).isNotEmpty;
    final contentScore = contentTokens.isEmpty
        ? 0.0
        : math.min(1.0, 0.55 + contentTokens.join().length / 24) *
            (hasStreetType ? 1.0 : 0.82);

    diagnostics.add('Contraste : ${imageQuality.contrast.toStringAsFixed(0)}.');
    diagnostics.add('Netteté : ${imageQuality.edgeEnergy.toStringAsFixed(0)}.');
    if (!hasStreetType) {
      diagnostics.add('Type de voie non visible : contrôle renforcé.');
    }

    final contrastScore =
        ((imageQuality.contrast - 18) / 34).clamp(0.0, 1.0).toDouble();
    final sharpnessScore =
        ((imageQuality.edgeEnergy - 7) / 24).clamp(0.0, 1.0).toDouble();
    final score = geometryScore * 0.24 +
        frameScore * 0.20 +
        backgroundScore * 0.12 +
        contrastScore * 0.15 +
        sharpnessScore * 0.17 +
        contentScore * 0.12;

    // Un cadre très discret reste possible sur certaines plaques. Le filtre
    // accepte donc aussi une zone géométriquement très convaincante et nette.
    final hasVisualContainer = frameScore >= 0.24 ||
        (geometryScore >= 0.90 && backgroundScore >= 0.42);

    return PlateCheckResult(
      score: score.clamp(0.0, 1.0).toDouble(),
      isProbablePlate: score >= 0.54 &&
          meaningfulLines.isNotEmpty &&
          hasVisualContainer &&
          sharpnessScore >= 0.18,
      diagnostics: diagnostics,
    );
  }

  Rect _expandedPlateBounds(Rect text, int width, int height) {
    final horizontalPadding = math.max(10.0, text.width * 0.18);
    final verticalPadding = math.max(8.0, text.height * 0.70);
    return Rect.fromLTRB(
      (text.left - horizontalPadding).clamp(2.0, width - 3.0).toDouble(),
      (text.top - verticalPadding).clamp(2.0, height - 3.0).toDouble(),
      (text.right + horizontalPadding).clamp(3.0, width - 2.0).toDouble(),
      (text.bottom + verticalPadding).clamp(3.0, height - 2.0).toDouble(),
    );
  }

  _PlateSurfaceEvidence _plateSurfaceEvidence(img.Image image, Rect rect) {
    if (rect.width < 18 || rect.height < 12) {
      return const _PlateSurfaceEvidence(
        frameScore: 0,
        backgroundUniformity: 0,
      );
    }

    const sampleCount = 36;
    const offset = 3;
    final sideStrengths = <double>[];

    double horizontalSide(double y, double insideY, double outsideY) {
      var sum = 0.0;
      for (var i = 0; i < sampleCount; i++) {
        final x = rect.left + rect.width * (i + 0.5) / sampleCount;
        final edge = _luminance(image, x.round(), y.round());
        final inside = _luminance(image, x.round(), insideY.round());
        final outside = _luminance(image, x.round(), outsideY.round());
        sum += math.max((edge - inside).abs(), (inside - outside).abs());
      }
      return sum / sampleCount;
    }

    double verticalSide(double x, double insideX, double outsideX) {
      var sum = 0.0;
      for (var i = 0; i < sampleCount; i++) {
        final y = rect.top + rect.height * (i + 0.5) / sampleCount;
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
    final strongSides = sideStrengths.where((strength) => strength >= 9).length;
    final edgeScore = ((averageEdge - 4) / 24).clamp(0.0, 1.0).toDouble();
    final coverageScore = strongSides / 4.0;
    final frameScore = edgeScore * 0.65 + coverageScore * 0.35;

    final colors = <_Rgb>[];
    const gridX = 12;
    const gridY = 7;
    for (var row = 0; row < gridY; row++) {
      for (var column = 0; column < gridX; column++) {
        // On échantillonne surtout les marges, en évitant la zone centrale où
        // se trouvent les lettres sombres.
        if (row >= 2 && row <= 4 && column >= 2 && column <= 9) {
          continue;
        }
        final x = rect.left + rect.width * (column + 0.5) / gridX;
        final y = rect.top + rect.height * (row + 0.5) / gridY;
        colors.add(_rgb(image, x.round(), y.round()));
      }
    }

    final backgroundUniformity = _colorUniformity(colors);
    return _PlateSurfaceEvidence(
      frameScore: frameScore.clamp(0.0, 1.0).toDouble(),
      backgroundUniformity: backgroundUniformity,
    );
  }

  double _colorUniformity(List<_Rgb> colors) {
    if (colors.isEmpty) {
      return 0;
    }
    final meanR = colors.fold<double>(0, (sum, color) => sum + color.r) /
        colors.length;
    final meanG = colors.fold<double>(0, (sum, color) => sum + color.g) /
        colors.length;
    final meanB = colors.fold<double>(0, (sum, color) => sum + color.b) /
        colors.length;
    var variance = 0.0;
    for (final color in colors) {
      variance += math.pow(color.r - meanR, 2).toDouble();
      variance += math.pow(color.g - meanG, 2).toDouble();
      variance += math.pow(color.b - meanB, 2).toDouble();
    }
    final deviation = math.sqrt(variance / (colors.length * 3));
    return (1 - deviation / 72).clamp(0.0, 1.0).toDouble();
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
    final step = math.max(1, math.min(image.width, image.height) ~/ 180);
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
