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
  final TransformationController _transformationController = TransformationController();

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
                            widget.onPointSelected!(projection.toGeo(details.localPosition));
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
            onPressed: () => _transformationController.value = Matrix4.identity(),
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

class _MapProjection {
  const _MapProjection(this.bounds, this.size);

  final GeoBounds bounds;
  final Size size;

  Offset toOffset(GeoPoint point) {
    final longitudeSpan = math.max(0.000001, bounds.maxLongitude - bounds.minLongitude);
    final latitudeSpan = math.max(0.000001, bounds.maxLatitude - bounds.minLatitude);
    final x = (point.longitude - bounds.minLongitude) / longitudeSpan * size.width;
    final y = (bounds.maxLatitude - point.latitude) / latitudeSpan * size.height;
    return Offset(x, y);
  }

  GeoPoint toGeo(Offset offset) {
    final longitude = bounds.minLongitude + offset.dx / size.width *
        (bounds.maxLongitude - bounds.minLongitude);
    final latitude = bounds.maxLatitude - offset.dy / size.height *
        (bounds.maxLatitude - bounds.minLatitude);
    return GeoPoint(latitude, longitude);
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
        oldDelegate.streets != streets;
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
