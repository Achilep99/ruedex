import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/street_entry.dart';
import 'rarity_badge.dart';

class ParisStreetMap extends StatefulWidget {
  const ParisStreetMap({
    required this.streets,
    required this.bounds,
    this.discoveredIds = const {},
    this.selectedPoint,
    this.onPointSelected,
    this.showLegend = true,
    super.key,
  });

  final List<StreetEntry> streets;
  final GeoBounds bounds;
  final Set<String> discoveredIds;
  final GeoPoint? selectedPoint;
  final ValueChanged<GeoPoint>? onPointSelected;
  final bool showLegend;

  @override
  State<ParisStreetMap> createState() => _ParisStreetMapState();
}

class _ParisStreetMapState extends State<ParisStreetMap> {
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final projection = _MapProjection(widget.bounds, size);
              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 9,
                  boundaryMargin: const EdgeInsets.all(120),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.onPointSelected == null
                        ? null
                        : (details) {
                            widget.onPointSelected!(
                              projection.toGeo(details.localPosition),
                            );
                          },
                    child: CustomPaint(
                      size: size,
                      painter: _ParisStreetPainter(
                        streets: widget.streets,
                        projection: projection,
                        discoveredIds: widget.discoveredIds,
                        selectedPoint: widget.selectedPoint,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton.filledTonal(
            tooltip: 'Recentrer la carte',
            onPressed: () {
              _transformationController.value = Matrix4.identity();
            },
            icon: const Icon(Icons.center_focus_strong),
          ),
        ),
        if (widget.showLegend)
          const Positioned(
            left: 12,
            bottom: 12,
            child: _MapLegend(),
          ),
      ],
    );
  }
}

/// Projection locale adaptée à Paris.
///
/// Deux corrections sont importantes :
/// - la longitude est multipliée par cos(latitude), car un degré de longitude
///   est plus court qu'un degré de latitude à Paris ;
/// - un seul facteur d'échelle est utilisé pour les deux axes, afin de ne
///   jamais étirer la ville pour remplir l'écran.
class _MapProjection {
  _MapProjection(this.bounds, this.size) {
    final centerLatitude =
        (bounds.minLatitude + bounds.maxLatitude) / 2.0;
    _centerLongitude =
        (bounds.minLongitude + bounds.maxLongitude) / 2.0;
    _longitudeFactor = math.cos(centerLatitude * math.pi / 180.0);

    _minProjectedX =
        (bounds.minLongitude - _centerLongitude) * _longitudeFactor;
    _maxProjectedX =
        (bounds.maxLongitude - _centerLongitude) * _longitudeFactor;

    final projectedWidth = math
        .max(0.000001, _maxProjectedX - _minProjectedX)
        .toDouble();
    final projectedHeight = math
        .max(
          0.000001,
          bounds.maxLatitude - bounds.minLatitude,
        )
        .toDouble();

    const padding = 18.0;
    final availableWidth =
        math.max(1.0, size.width - padding * 2).toDouble();
    final availableHeight =
        math.max(1.0, size.height - padding * 2).toDouble();

    _scale = math
        .min(
          availableWidth / projectedWidth,
          availableHeight / projectedHeight,
        )
        .toDouble();

    final renderedWidth = projectedWidth * _scale;
    final renderedHeight = projectedHeight * _scale;
    _offsetX = (size.width - renderedWidth) / 2.0;
    _offsetY = (size.height - renderedHeight) / 2.0;
  }

  final GeoBounds bounds;
  final Size size;

  late final double _centerLongitude;
  late final double _longitudeFactor;
  late final double _minProjectedX;
  late final double _maxProjectedX;
  late final double _scale;
  late final double _offsetX;
  late final double _offsetY;

  Offset toOffset(GeoPoint point) {
    final projectedX =
        (point.longitude - _centerLongitude) * _longitudeFactor;
    final x = _offsetX + (projectedX - _minProjectedX) * _scale;
    final y = _offsetY +
        (bounds.maxLatitude - point.latitude) * _scale;
    return Offset(x, y);
  }

  GeoPoint toGeo(Offset offset) {
    final projectedX =
        _minProjectedX + (offset.dx - _offsetX) / _scale;
    final longitude =
        _centerLongitude + projectedX / _longitudeFactor;
    final latitude =
        bounds.maxLatitude - (offset.dy - _offsetY) / _scale;

    return GeoPoint(
      latitude.clamp(bounds.minLatitude, bounds.maxLatitude).toDouble(),
      longitude.clamp(bounds.minLongitude, bounds.maxLongitude).toDouble(),
    );
  }
}

class _ParisStreetPainter extends CustomPainter {
  const _ParisStreetPainter({
    required this.streets,
    required this.projection,
    required this.discoveredIds,
    required this.selectedPoint,
  });

  final List<StreetEntry> streets;
  final _MapProjection projection;
  final Set<String> discoveredIds;
  final GeoPoint? selectedPoint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF10141B),
    );

    final paths = <StreetRarity, Path>{
      for (final rarity in StreetRarity.values) rarity: Path(),
    };
    final undiscoveredPath = Path();

    for (final street in streets) {
      final target = discoveredIds.contains(street.id)
          ? paths[street.rarity]!
          : undiscoveredPath;
      for (final segment in street.segments) {
        if (segment.length < 2) {
          continue;
        }
        final first = projection.toOffset(segment.first);
        target.moveTo(first.dx, first.dy);
        for (final point in segment.skip(1)) {
          final projected = projection.toOffset(point);
          target.lineTo(projected.dx, projected.dy);
        }
      }
    }

    canvas.drawPath(
      undiscoveredPath,
      Paint()
        ..color = const Color(0xFFB8C0CA).withValues(alpha: 0.48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..strokeCap = StrokeCap.round,
    );

    for (final entry in paths.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = rarityColor(entry.key)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    final marker = selectedPoint;
    if (marker != null) {
      final center = projection.toOffset(marker);
      canvas.drawCircle(center, 9, Paint()..color = Colors.white);
      canvas.drawCircle(center, 6, Paint()..color = const Color(0xFFE84368));
    }
  }

  @override
  bool shouldRepaint(covariant _ParisStreetPainter oldDelegate) {
    return oldDelegate.discoveredIds != discoveredIds ||
        oldDelegate.selectedPoint != selectedPoint ||
        oldDelegate.streets != streets ||
        oldDelegate.projection.size != projection.size;
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6191E27),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          'Gris : à découvrir\nCouleur : capturée',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
