import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/ocr_scan_result.dart';

class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrScanResult> recognizeImage(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(image);
    final lines = <OcrLineResult>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        lines.add(OcrLineResult(text: line.text, boundingBox: line.boundingBox));
      }
    }
    return OcrScanResult(fullText: result.text, lines: lines);
  }

  void dispose() => _recognizer.close();
}
