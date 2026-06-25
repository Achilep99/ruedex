import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/match_candidate.dart';
import '../models/street_entry.dart';
import '../services/discovery_store.dart';
import '../services/location_service.dart';
import '../services/ocr_service.dart';
import '../services/street_matcher.dart';
import '../widgets/rarity_badge.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    required this.streets,
    required this.discoveryStore,
    super.key,
  });

  final List<StreetEntry> streets;
  final DiscoveryStore discoveryStore;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final OcrService _ocrService = OcrService();
  final LocationService _locationService = LocationService();
  final StreetMatcher _matcher = const StreetMatcher();

  final TextEditingController _simulatedTextController = TextEditingController(
    text: 'RUE VICT0R HUG0',
  );
  final TextEditingController _latitudeController = TextEditingController(
    text: '48.8706',
  );
  final TextEditingController _longitudeController = TextEditingController(
    text: '2.2854',
  );

  XFile? _image;
  String _recognizedText = '';
  List<MatchCandidate> _candidates = const [];
  MatchCandidate? _selectedCandidate;
  bool _developerMode = true;
  bool _processing = false;
  String? _error;
  double? _latitude;
  double? _longitude;

  @override
  void dispose() {
    _ocrService.dispose();
    _simulatedTextController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 2400,
    );
    if (image == null) return;

    setState(() {
      _image = image;
      _error = null;
    });
    await _runOcr();
  }

  Future<void> _runOcr() async {
    final image = _image;
    if (image == null) return;

    setState(() {
      _processing = true;
      _error = null;
      _candidates = const [];
      _selectedCandidate = null;
    });

    try {
      final text = await _ocrService.recognizeImage(image.path);
      if (!mounted) return;
      setState(() => _recognizedText = text);
      await _match(text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'OCR impossible : $error');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _useRealGps() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
      if (_recognizedText.isNotEmpty) {
        await _match(_recognizedText);
      }
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'GPS impossible : $error');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _analyzeSimulatedText() async {
    final latitude = double.tryParse(_latitudeController.text.replaceAll(',', '.'));
    final longitude = double.tryParse(_longitudeController.text.replaceAll(',', '.'));

    setState(() {
      _latitude = latitude;
      _longitude = longitude;
      _recognizedText = _simulatedTextController.text;
      _error = null;
    });

    await _match(_recognizedText);
  }

  Future<void> _match(String text) async {
    final results = _matcher.findCandidates(
      recognizedText: text,
      streets: widget.streets,
      latitude: _latitude,
      longitude: _longitude,
    );

    if (!mounted) return;
    setState(() {
      _candidates = results;
      _selectedCandidate = results.isEmpty ? null : results.first;
    });
  }

  Future<void> _validateSelection() async {
    final selected = _selectedCandidate;
    if (selected == null) return;

    await widget.discoveryStore.addDiscovery(selected.street.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle rue découverte !'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected.street.officialName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            RarityBadge(rarity: selected.street.rarity),
            const SizedBox(height: 16),
            Text(selected.street.summary),
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

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCandidate;
    final automaticallyValid = selected != null && _matcher.canValidate(selected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner une plaque'),
        actions: [
          Row(
            children: [
              const Text('Dev'),
              Switch(
                value: _developerMode,
                onChanged: (value) => setState(() => _developerMode = value),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ImagePanel(image: _image),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _processing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Caméra'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galerie'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _processing ? null : _useRealGps,
              icon: const Icon(Icons.my_location),
              label: const Text('Utiliser le vrai GPS'),
            ),
            if (_processing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_developerMode) ...[
              const SizedBox(height: 22),
              _DeveloperPanel(
                simulatedTextController: _simulatedTextController,
                latitudeController: _latitudeController,
                longitudeController: _longitudeController,
                recognizedText: _recognizedText,
                onAnalyze: _processing ? null : _analyzeSimulatedText,
              ),
            ],
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('Candidats', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              ..._candidates.map(
                (candidate) => _CandidateCard(
                  candidate: candidate,
                  selected: identical(candidate, _selectedCandidate),
                  showDebug: _developerMode,
                  onTap: () => setState(() => _selectedCandidate = candidate),
                ),
              ),
              const SizedBox(height: 12),
              if (!automaticallyValid)
                const Text(
                  'Le score automatique est trop faible. En mode développeur, tu peux quand même confirmer la bonne rue pour tester le reste du jeu.',
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: selected == null || (!automaticallyValid && !_developerMode)
                    ? null
                    : _validateSelection,
                icon: const Icon(Icons.add_task),
                label: Text(
                  automaticallyValid ? 'Valider la découverte' : 'Forcer la validation (dev)',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({required this.image});

  final XFile? image;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: image == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.signpost_outlined, size: 58),
                      SizedBox(height: 10),
                      Text('Cadre la plaque de rue'),
                    ],
                  ),
                )
              : Image.file(
                  File(image!.path),
                  fit: BoxFit.cover,
                ),
        ),
      ),
    );
  }
}

class _DeveloperPanel extends StatelessWidget {
  const _DeveloperPanel({
    required this.simulatedTextController,
    required this.latitudeController,
    required this.longitudeController,
    required this.recognizedText,
    required this.onAnalyze,
  });

  final TextEditingController simulatedTextController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final String recognizedText;
  final VoidCallback? onAnalyze;

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
          Text('Mode développeur', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: simulatedTextController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Texte OCR simulé',
              hintText: 'Ex. RUE VICT0R HUG0',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latitudeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: longitudeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Tester la reconnaissance'),
          ),
          if (recognizedText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Texte réellement lu', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SelectableText(recognizedText),
          ],
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.selected,
    required this.showDebug,
    required this.onTap,
  });

  final MatchCandidate candidate;
  final bool selected;
  final bool showDebug;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = candidate.distanceMeters;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: selected,
                  onChanged: (_) => onTap(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.street.officialName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('${candidate.percentage} % de confiance'),
                      if (distance != null)
                        Text('Distance : ${distance.round()} m'),
                      if (showDebug) ...[
                        const SizedBox(height: 6),
                        Text('OCR : ${candidate.textPercentage} %'),
                        Text('Fragment : “${candidate.matchedFragment}”'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
