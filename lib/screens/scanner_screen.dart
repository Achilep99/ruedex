import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/geo_point.dart';
import '../models/match_candidate.dart';
import '../models/ocr_scan_result.dart';
import '../models/plate_check_result.dart';
import '../models/street_database.dart';
import '../services/discovery_store.dart';
import '../services/location_service.dart';
import '../services/ocr_service.dart';
import '../services/online_game_service.dart';
import '../services/plate_heuristic_service.dart';
import '../services/scan_frame_service.dart';
import '../services/street_matcher.dart';
import '../widgets/rarity_badge.dart';
import 'coordinate_picker_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    required this.database,
    required this.discoveryStore,
    required this.onlineGameService,
    required this.developerMode,
    super.key,
  });

  final StreetDatabase database;
  final DiscoveryStore discoveryStore;
  final OnlineGameService onlineGameService;
  final bool developerMode;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  final OcrService _ocrService = OcrService();
  final LocationService _locationService = LocationService();
  final PlateHeuristicService _plateHeuristic = const PlateHeuristicService();
  final ScanFrameService _scanFrameService = const ScanFrameService();
  final StreetMatcher _matcher = const StreetMatcher();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _simulatedTextController = TextEditingController(
    text: 'RUE RENE BOULANGER',
  );

  CameraController? _cameraController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _realPosition;
  GeoPoint? _manualPoint;
  OcrScanResult? _lastOcr;
  PlateCheckResult? _lastPlateCheck;
  List<MatchCandidate> _candidates = const [];
  MatchDecision? _decision;
  MatchCandidate? _selectedCandidate;

  bool _initializing = true;
  bool _processingFrame = false;
  bool _completed = false;
  bool _timedOut = false;
  bool _cameraPaused = false;
  bool _ignoreVisualPlateFilter = false;
  String _status = 'Initialisation de la caméra et du GPS…';
  String? _error;
  int _attemptCount = 0;
  String? _stableStreetId;
  int _stableCount = 0;
  DateTime _scanStartedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraPaused = true;
    } else if (state == AppLifecycleState.resumed) {
      _cameraPaused = false;
      if (!_completed && !_timedOut) _scanLoop();
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _error = null;
      _status = 'Recherche de ta position…';
    });

    await _initializeLocation();
    await _initializeCamera();

    if (!mounted) return;
    setState(() {
      _initializing = false;
      _status = _currentPoint == null
          ? 'GPS indisponible : impossible de valider une rue.'
          : 'Recherche d’une plaque… vise-la approximativement et reste immobile.';
    });
    _scanStartedAt = DateTime.now();
    _scanLoop();
  }

  Future<void> _initializeLocation() async {
    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      setState(() => _realPosition = position);
      _positionSubscription = _locationService.positionStream().listen(
        (position) {
          if (mounted && _manualPoint == null) {
            setState(() => _realPosition = position);
          }
        },
        onError: (_) {},
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Aucune caméra disponible.');
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraController = controller);
    } catch (error) {
      if (mounted) setState(() => _error = 'Caméra impossible : $error');
    }
  }

  GeoPoint? get _currentPoint {
    if (widget.developerMode && _manualPoint != null) return _manualPoint;
    final position = _realPosition;
    return position == null ? null : GeoPoint(position.latitude, position.longitude);
  }

  double? get _currentAccuracy =>
      widget.developerMode && _manualPoint != null ? 5 : _realPosition?.accuracy;

  Future<void> _scanLoop() async {
    if (_processingFrame || _completed || _timedOut || _cameraPaused) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _processingFrame = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted || _completed || _timedOut || _cameraPaused) return;
      final image = await controller.takePicture();
      _attemptCount++;
      try {
        await _analyzeImage(image.path, requireStableFrames: true);
      } finally {
        final file = File(image.path);
        if (await file.exists()) {
          await file.delete();
        }
      }

      if (!_completed &&
          DateTime.now().difference(_scanStartedAt) > const Duration(seconds: 15)) {
        if (mounted) {
          setState(() {
            _timedOut = true;
            _status = 'Plaque non reconnue. Rapproche-toi, garde-la visible ou améliore la lumière.';
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Analyse caméra impossible : $error');
    } finally {
      _processingFrame = false;
      if (mounted && !_completed && !_timedOut && !_cameraPaused) {
        unawaited(_scanLoop());
      }
    }
  }

  Future<void> _analyzeImage(
    String imagePath, {
    required bool requireStableFrames,
  }) async {
    final point = _currentPoint;
    final framedImagePath = await _scanFrameService.cropToScanArea(imagePath);
    final framedImageIsTemporary = framedImagePath != imagePath;
    late final OcrScanResult ocr;
    late final PlateCheckResult plateCheck;
    try {
      ocr = await _ocrService.recognizeImage(framedImagePath);
      plateCheck = await _plateHeuristic.analyze(framedImagePath, ocr);
    } finally {
      if (framedImageIsTemporary) {
        final temporaryFile = File(framedImagePath);
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }
    }
    final candidates = _matcher.findCandidates(
      recognizedText: ocr.fullText,
      streets: widget.database.streets,
      latitude: point?.latitude,
      longitude: point?.longitude,
      gpsAccuracyMeters: _currentAccuracy,
    );
    final decision = _matcher.decide(
      candidates,
      gpsAccuracyMeters: _currentAccuracy,
      requireGps: true,
    );

    final visualFilterBypassed =
        widget.developerMode && _ignoreVisualPlateFilter;
    final plateAccepted =
        plateCheck.isProbablePlate || visualFilterBypassed;

    if (!mounted) return;
    setState(() {
      _lastOcr = ocr;
      _lastPlateCheck = plateCheck;
      _candidates = candidates;
      _decision = decision;
      _selectedCandidate = candidates.isEmpty ? null : candidates.first;
      if (plateAccepted) {
        _status = visualFilterBypassed
            ? 'Filtre visuel ignoré en mode développeur. ${decision.reason}'
            : decision.reason;
      } else {
        _status =
            'Aucune zone ne ressemble encore assez à une plaque de rue.';
      }
    });

    if (!plateAccepted || !decision.accepted || decision.best == null) {
      _stableStreetId = null;
      _stableCount = 0;
      return;
    }

    final id = decision.best!.street.id;
    if (_stableStreetId == id) {
      _stableCount++;
    } else {
      _stableStreetId = id;
      _stableCount = 1;
    }

    final requiredCount = requireStableFrames ? 2 : 1;
    if (_stableCount >= requiredCount) {
      await _completeDiscovery(decision.best!);
    } else if (mounted) {
      setState(() => _status = 'Nom repéré. Vérification sur une seconde image…');
    }
  }

  Future<void> _completeDiscovery(MatchCandidate candidate) async {
    if (_completed) return;
    _completed = true;
    final isNew = await widget.discoveryStore.addDiscovery(candidate.street.id);
    CaptureResult? onlineCapture;
    if (widget.onlineGameService.isConfigured) {
      try {
        onlineCapture = await widget.onlineGameService.captureStreet(
          candidate: candidate,
          plateScore: _lastPlateCheck?.score ?? 0,
        );
      } catch (error) {
        onlineCapture = CaptureResult(
          accepted: false,
          message: 'Capture locale OK, serveur refusé : $error',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      if (onlineCapture == null) {
        _status = isNew ? 'Rue capturée !' : 'Rue déjà présente dans ton RueDex.';
      } else if (onlineCapture.accepted) {
        _status = 'Rue capturée pour ton équipe !';
      } else {
        _status = onlineCapture.message;
      }
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isNew ? 'Nouvelle rue découverte !' : 'Rue déjà découverte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.street.officialName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            RarityBadge(rarity: candidate.street.rarity),
            if (onlineCapture != null) ...[
              const SizedBox(height: 12),
              Text(onlineCapture.accepted
                  ? 'Saison : ${onlineCapture.message}'
                  : 'Saison non mise à jour : ${onlineCapture.message}'),
            ],
            if (candidate.street.hasVerifiedOrigin) ...[
              const SizedBox(height: 16),
              Text(candidate.street.origin),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _timedOut = false;
      _completed = false;
      _attemptCount = 0;
      _stableStreetId = null;
      _stableCount = 0;
      _status = 'Recherche d’une plaque… vise-la approximativement et reste immobile.';
      _error = null;
    });
    _scanStartedAt = DateTime.now();
    _scanLoop();
  }

  Future<void> _pickDeveloperImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2600,
    );
    if (image == null) return;
    setState(() {
      _timedOut = true;
      _status = 'Analyse de l’image de test…';
    });
    try {
      await _analyzeImage(image.path, requireStableFrames: false);
    } catch (error) {
      if (mounted) setState(() => _error = 'Image de test impossible : $error');
    }
  }

  Future<void> _chooseManualGps() async {
    final point = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute(
        builder: (_) => CoordinatePickerScreen(
          database: widget.database,
          initialPoint: _currentPoint,
        ),
      ),
    );
    if (point == null || !mounted) return;
    setState(() {
      _manualPoint = point;
      _status = 'GPS de test placé sur la carte.';
    });
  }

  Future<void> _useRealGps() async {
    setState(() => _manualPoint = null);
    try {
      final position = await _locationService.determinePosition();
      if (mounted) setState(() => _realPosition = position);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _testSimulatedText() async {
    final point = _currentPoint;
    final text = _simulatedTextController.text;
    final candidates = _matcher.findCandidates(
      recognizedText: text,
      streets: widget.database.streets,
      latitude: point?.latitude,
      longitude: point?.longitude,
      gpsAccuracyMeters: _currentAccuracy,
    );
    final decision = _matcher.decide(
      candidates,
      gpsAccuracyMeters: _currentAccuracy,
      requireGps: true,
    );
    if (!mounted) return;
    setState(() {
      _timedOut = true;
      _lastOcr = OcrScanResult(fullText: text, lines: const []);
      _lastPlateCheck = const PlateCheckResult(
        score: 1,
        isProbablePlate: true,
        diagnostics: ['Filtre plaque ignoré pour le texte simulé.'],
      );
      _candidates = candidates;
      _decision = decision;
      _selectedCandidate = candidates.isEmpty ? null : candidates.first;
      _status = decision.reason;
    });
  }

  Future<void> _forceSelected() async {
    final candidate = _selectedCandidate;
    if (candidate != null) await _completeDiscovery(candidate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _cameraController?.dispose();
    _ocrService.dispose();
    _simulatedTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final gpsPoint = _currentPoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner une plaque'),
        actions: [
          if (gpsPoint != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'GPS ±${(_currentAccuracy ?? 0).round()} m',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: _initializing || controller == null || !controller.value.isInitialized
                          ? const Center(child: CircularProgressIndicator())
                          : CameraPreview(controller),
                    ),
                    const _ScannerFrameOverlay(),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xD9141820),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_timedOut && !_completed) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer le scan direct'),
              ),
            ],
            if (widget.developerMode) ...[
              const SizedBox(height: 18),
              _DeveloperPanel(
                currentPoint: gpsPoint,
                simulatedTextController: _simulatedTextController,
                onChooseGps: _chooseManualGps,
                onUseRealGps: _useRealGps,
                onPickImage: _pickDeveloperImage,
                onTestText: _testSimulatedText,
                ignoreVisualPlateFilter: _ignoreVisualPlateFilter,
                onIgnoreVisualPlateFilterChanged: (value) {
                  setState(() => _ignoreVisualPlateFilter = value);
                },
              ),
              if (_lastOcr != null || _lastPlateCheck != null) ...[
                const SizedBox(height: 14),
                _DebugReadout(
                  ocr: _lastOcr,
                  plateCheck: _lastPlateCheck,
                  decision: _decision,
                  attempts: _attemptCount,
                ),
              ],
              if (_candidates.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Candidats GPS + OCR', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ..._candidates.map(
                  (candidate) => _CandidateCard(
                    candidate: candidate,
                    selected: identical(candidate, _selectedCandidate),
                    onTap: () => setState(() => _selectedCandidate = candidate),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _selectedCandidate == null ? null : _forceSelected,
                  icon: const Icon(Icons.build),
                  label: const Text('Forcer ce candidat (développeur)'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ScannerFrameOverlay extends StatelessWidget {
  const _ScannerFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ScannerGuidePainter()),
          ),
          const Positioned(
            top: 14,
            left: 18,
            right: 18,
            child: Text(
              'La plaque peut être décalée, inclinée ou de forme carrée',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final guide = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.90,
      height: size.height * 0.56,
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final corner =
        math.min(34.0, guide.shortestSide * 0.15).toDouble();

    canvas.drawLine(guide.topLeft, guide.topLeft + Offset(corner, 0), paint);
    canvas.drawLine(guide.topLeft, guide.topLeft + Offset(0, corner), paint);
    canvas.drawLine(guide.topRight, guide.topRight - Offset(corner, 0), paint);
    canvas.drawLine(guide.topRight, guide.topRight + Offset(0, corner), paint);
    canvas.drawLine(
      guide.bottomLeft,
      guide.bottomLeft + Offset(corner, 0),
      paint,
    );
    canvas.drawLine(
      guide.bottomLeft,
      guide.bottomLeft - Offset(0, corner),
      paint,
    );
    canvas.drawLine(
      guide.bottomRight,
      guide.bottomRight - Offset(corner, 0),
      paint,
    );
    canvas.drawLine(
      guide.bottomRight,
      guide.bottomRight - Offset(0, corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerGuidePainter oldDelegate) => false;
}

class _DeveloperPanel extends StatelessWidget {
  const _DeveloperPanel({
    required this.currentPoint,
    required this.simulatedTextController,
    required this.onChooseGps,
    required this.onUseRealGps,
    required this.onPickImage,
    required this.onTestText,
    required this.ignoreVisualPlateFilter,
    required this.onIgnoreVisualPlateFilterChanged,
  });

  final GeoPoint? currentPoint;
  final TextEditingController simulatedTextController;
  final VoidCallback onChooseGps;
  final VoidCallback onUseRealGps;
  final VoidCallback onPickImage;
  final VoidCallback onTestText;
  final bool ignoreVisualPlateFilter;
  final ValueChanged<bool> onIgnoreVisualPlateFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outils développeur', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            currentPoint == null
                ? 'Aucune position active'
                : '${currentPoint!.latitude.toStringAsFixed(6)}, ${currentPoint!.longitude.toStringAsFixed(6)}',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onChooseGps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Choisir sur la carte'),
              ),
              OutlinedButton.icon(
                onPressed: onUseRealGps,
                icon: const Icon(Icons.my_location),
                label: const Text('GPS réel'),
              ),
              OutlinedButton.icon(
                onPressed: onPickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Importer une image'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ignorer le filtre visuel de plaque'),
            subtitle: const Text(
              'Seulement pour tester séparément l’OCR et le GPS.',
            ),
            value: ignoreVisualPlateFilter,
            onChanged: onIgnoreVisualPlateFilterChanged,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: simulatedTextController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Texte OCR simulé'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onTestText,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Tester le texte'),
          ),
        ],
      ),
    );
  }
}

class _DebugReadout extends StatelessWidget {
  const _DebugReadout({
    required this.ocr,
    required this.plateCheck,
    required this.decision,
    required this.attempts,
  });

  final OcrScanResult? ocr;
  final PlateCheckResult? plateCheck;
  final MatchDecision? decision;
  final int attempts;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Détails de l’analyse'),
      subtitle: Text('$attempts image(s) analysée(s)'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plateCheck != null) ...[
          Text('Plaque probable : ${plateCheck!.percentage} %'),
          ...plateCheck!.diagnostics.map((line) => Text(line)),
          const SizedBox(height: 10),
        ],
        if (decision != null) Text('Décision : ${decision!.reason}'),
        if (ocr != null && ocr!.fullText.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Texte OCR :'),
          SelectableText(ocr!.fullText),
        ],
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final MatchCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(candidate.street.officialName),
        subtitle: Text(
          'Score ${candidate.percentage} % · nom ${candidate.textPercentage} % · couverture ${candidate.coveragePercentage} %'
          '${candidate.distanceMeters == null ? '' : ' · ${candidate.distanceMeters!.round()} m'}',
        ),
      ),
    );
  }
}
