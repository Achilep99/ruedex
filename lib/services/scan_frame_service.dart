import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Prépare une image de caméra pour l'OCR sans imposer la position du cadre.
///
/// Le cadre affiché à l'écran est uniquement un guide. La plaque peut être
/// décalée, inclinée, carrée ou allongée : presque toute la photo est analysée.
/// On retire seulement une marge minime et on réduit les très grandes images
/// afin de garder un scan suffisamment rapide sur téléphone.
class ScanFrameService {
  const ScanFrameService();

  Future<String> cropToScanArea(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) {
      return imagePath;
    }

    image = img.bakeOrientation(image);

    final horizontalMargin =
        math.max(0, (image.width * 0.015).round()).toInt();
    final verticalMargin =
        math.max(0, (image.height * 0.015).round()).toInt();
    final cropWidth = image.width - horizontalMargin * 2;
    final cropHeight = image.height - verticalMargin * 2;

    if (cropWidth > 20 && cropHeight > 20) {
      image = img.copyCrop(
        image,
        x: horizontalMargin,
        y: verticalMargin,
        width: cropWidth,
        height: cropHeight,
      );
    }

    const maximumDimension = 1800;
    final longestSide = math.max(image.width, image.height).toInt();
    if (longestSide > maximumDimension) {
      if (image.width >= image.height) {
        image = img.copyResize(image, width: maximumDimension);
      } else {
        image = img.copyResize(image, height: maximumDimension);
      }
    }

    final output = File(
      '${Directory.systemTemp.path}/ruedex_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(
      img.encodeJpg(image, quality: 92),
      flush: true,
    );
    return output.path;
  }
}
