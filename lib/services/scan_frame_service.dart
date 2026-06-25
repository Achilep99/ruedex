import 'dart:io';

import 'package:image/image.dart' as img;

/// Extrait la zone centrale dessinée dans l'aperçu du scanner.
///
/// Le but est d'éviter qu'une enseigne ou une affiche située ailleurs dans la
/// photo soit envoyée à l'OCR. Le recadrage est volontairement un peu plus
/// large que le cadre visible pour tolérer les différences de ratio caméra.
class ScanFrameService {
  const ScanFrameService();

  Future<String> cropToScanArea(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return imagePath;
    image = img.bakeOrientation(image);

    final cropWidth = (image.width * 0.92).round();
    final cropHeight = (image.height * 0.42).round();
    final cropX = ((image.width - cropWidth) / 2).round();
    final cropY = ((image.height - cropHeight) / 2).round();
    var cropped = img.copyCrop(
      image,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );
    if (cropped.width > 1800) {
      cropped = img.copyResize(cropped, width: 1800);
    }

    final output = File(
      '${Directory.systemTemp.path}/ruedex_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
    return output.path;
  }
}
