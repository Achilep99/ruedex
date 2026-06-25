import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/street_database.dart';
import '../widgets/paris_street_map.dart';

class CoordinatePickerScreen extends StatefulWidget {
  const CoordinatePickerScreen({
    required this.database,
    this.initialPoint,
    super.key,
  });

  final StreetDatabase database;
  final GeoPoint? initialPoint;

  @override
  State<CoordinatePickerScreen> createState() => _CoordinatePickerScreenState();
}

class _CoordinatePickerScreenState extends State<CoordinatePickerScreen> {
  GeoPoint? _point;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Position GPS simulée')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(
              _point == null
                  ? 'Touche la carte pour placer le GPS de test.'
                  : '${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ParisStreetMap(
                streets: widget.database.streets,
                bounds: widget.database.bounds,
                selectedPoint: _point,
                showLegend: false,
                onPointSelected: (point) => setState(() => _point = point),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _point == null ? null : () => Navigator.of(context).pop(_point),
                  icon: const Icon(Icons.check),
                  label: const Text('Utiliser cette position'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
