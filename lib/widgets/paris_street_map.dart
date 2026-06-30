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
    this.teamOwnership = const {},
    this.teamColorResolver,
    this.onPointSelected,
    this.showLegend = true,
    super.key,
  });

  final List<StreetEntry> streets;
  final GeoBounds bounds;
  final Set<String> discoveredIds;
  final GeoPoint? selectedPoint;
  final Map<String, String> teamOwnership;
  final Color? Function(String? teamId)? teamColorResolver;
  final ValueChanged<GeoPoint>? onPointSelected;
  final bool showLegend;

  @override
  State<ParisStreetMap> createState() => _ParisStreetMapState();
}

class _ParisStreetMapState extends State<ParisStreetMap> {
  final TransformationController _transformationController =
      TransformationController();

  late _ProjectionDomain _domain;

  @override
  void initState() {
    super.initState();
    _domain = _ProjectionDomain.fromStreets(
      widget.streets,
      fallbackBounds: widget.bounds,
    );
  }

  @override
  void didUpdateWidget(covariant ParisStreetMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.streets, widget.streets) ||
        oldWidget.bounds != widget.bounds) {
      _domain = _ProjectionDomain.fromStreets(
        widget.streets,
        fallbackBounds: widget.bounds,
      );
      _transformationController.value = Matrix4.identity();
    }
  }

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
              final projection = _MapProjection(_domain, size);

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
                        teamOwnership: widget.teamOwnership,
                        teamColorResolver: widget.teamColorResolver,
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

class _ProjectionDomain {
  const _ProjectionDomain({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  factory _ProjectionDomain.fromStreets(
    List<StreetEntry> streets, {
    required GeoBounds fallbackBounds,
  }) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final street in streets) {
      for (final segment in street.segments) {
        for (final rawPoint in segment) {
          final point = _normaliseParisPoint(rawPoint);
          final projected = _project(point);
          minX = math.min(minX, projected.dx);
          maxX = math.max(maxX, projected.dx);
          minY = math.min(minY, projected.dy);
          maxY = math.max(maxY, projected.dy);
        }
      }
    }

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      final southWest = _project(
        GeoPoint(fallbackBounds.minLatitude, fallbackBounds.minLongitude),
      );
      final northEast = _project(
        GeoPoint(fallbackBounds.maxLatitude, fallbackBounds.maxLongitude),
      );
      minX = math.min(southWest.dx, northEast.dx);
      maxX = math.max(southWest.dx, northEast.dx);
      minY = math.min(southWest.dy, northEast.dy);
      maxY = math.max(southWest.dy, northEast.dy);
    }

    final width = math.max(0.000001, maxX - minX);
    final height = math.max(0.000001, maxY - minY);
    final xPadding = width * 0.025;
    final yPadding = height * 0.025;

    return _ProjectionDomain(
      minX: minX - xPadding,
      maxX: maxX + xPadding,
      minY: minY - yPadding,
      maxY: maxY + yPadding,
    );
  }
}

/// Projection Web Mercator calculée directement depuis les vrais tronçons.
///
/// On ne fait plus confiance aux dimensions déjà enregistrées dans les
/// métadonnées. Un seul facteur d'échelle est utilisé pour les deux axes : la
/// carte ne peut donc plus être étirée pour remplir un écran vertical.
class _MapProjection {
  _MapProjection(this.domain, this.size) {
    final projectedWidth = math.max(0.000001, domain.maxX - domain.minX);
    final projectedHeight = math.max(0.000001, domain.maxY - domain.minY);

    const padding = 18.0;
    final availableWidth = math.max(1.0, size.width - padding * 2);
    final availableHeight = math.max(1.0, size.height - padding * 2);

    _scale = math.min(
      availableWidth / projectedWidth,
      availableHeight / projectedHeight,
    );

    final renderedWidth = projectedWidth * _scale;
    final renderedHeight = projectedHeight * _scale;
    _offsetX = (size.width - renderedWidth) / 2.0;
    _offsetY = (size.height - renderedHeight) / 2.0;
  }

  final _ProjectionDomain domain;
  final Size size;

  late final double _scale;
  late final double _offsetX;
  late final double _offsetY;

  Offset toOffset(GeoPoint rawPoint) {
    final point = _normaliseParisPoint(rawPoint);
    final projected = _project(point);
    final x = _offsetX + (projected.dx - domain.minX) * _scale;
    final y = _offsetY + (domain.maxY - projected.dy) * _scale;
    return Offset(x, y);
  }

  GeoPoint toGeo(Offset offset) {
    final projectedX = domain.minX + (offset.dx - _offsetX) / _scale;
    final projectedY = domain.maxY - (offset.dy - _offsetY) / _scale;
    return _unproject(Offset(projectedX, projectedY));
  }
}

GeoPoint _normaliseParisPoint(GeoPoint point) {
  final looksNormal = point.latitude >= 47.0 &&
      point.latitude <= 50.0 &&
      point.longitude >= 1.0 &&
      point.longitude <= 4.0;
  if (looksNormal) {
    return point;
  }

  final looksSwapped = point.longitude >= 47.0 &&
      point.longitude <= 50.0 &&
      point.latitude >= 1.0 &&
      point.latitude <= 4.0;
  if (looksSwapped) {
    return GeoPoint(point.longitude, point.latitude);
  }

  return point;
}

Offset _project(GeoPoint point) {
  final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
  final longitudeRadians = point.longitude * math.pi / 180.0;
  final latitudeRadians = latitude * math.pi / 180.0;
  final mercatorY = math.log(
    math.tan(math.pi / 4.0 + latitudeRadians / 2.0),
  );
  return Offset(longitudeRadians, mercatorY);
}

GeoPoint _unproject(Offset projected) {
  final longitude = projected.dx * 180.0 / math.pi;
  final latitude =
      math.atan(math.sinh(projected.dy)) * 180.0 / math.pi;
  return GeoPoint(latitude, longitude);
}

class _ParisStreetPainter extends CustomPainter {
  const _ParisStreetPainter({
    required this.streets,
    required this.projection,
    required this.discoveredIds,
    required this.selectedPoint,
    required this.teamOwnership,
    required this.teamColorResolver,
  });

  final List<StreetEntry> streets;
  final _MapProjection projection;
  final Set<String> discoveredIds;
  final GeoPoint? selectedPoint;
  final Map<String, String> teamOwnership;
  final Color? Function(String? teamId)? teamColorResolver;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF10141B),
    );

    final rarityPaths = <StreetRarity, Path>{
      for (final rarity in StreetRarity.values) rarity: Path(),
    };
    final teamPaths = <String, Path>{};
    final undiscoveredPath = Path();

    for (final street in streets) {
      final teamId = teamOwnership[street.id];
      final Path target;
      if (teamId != null) {
        target = teamPaths.putIfAbsent(teamId, () => Path());
      } else if (discoveredIds.contains(street.id)) {
        target = rarityPaths[street.rarity]!;
      } else {
        target = undiscoveredPath;
      }

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

    for (final entry in rarityPaths.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = rarityColor(entry.key)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final entry in teamPaths.entries) {
      final color = teamColorResolver?.call(entry.key) ?? const Color(0xFFFFFFFF);
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.7
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
        oldDelegate.teamOwnership != teamOwnership ||
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
          'Gris : à découvrir\nCouleur : équipe ou rareté',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
