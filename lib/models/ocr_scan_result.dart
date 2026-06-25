import 'dart:ui';

class OcrLineResult {
  const OcrLineResult({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;
}

class OcrScanResult {
  const OcrScanResult({required this.fullText, required this.lines});

  final String fullText;
  final List<OcrLineResult> lines;
}
