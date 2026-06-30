import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/street_entry.dart';
import 'rarity_badge.dart';

enum MapLegendMode { rarity, teams }

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
    this.legendMode = MapLegendMode.rarity,
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
  final MapLegendMode legendMode;

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1118),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final canvasSize = _domain.fittedCanvasSize(viewport);
                  final projection = _MapProjection(_domain, canvasSize);

                  return InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1,
                    maxScale: 12,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(180),
                    child: SizedBox(
                      width: viewport.width,
                      height: viewport.height,
                      child: Center(
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
                            size: canvasSize,
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
            const Positioned(
              top: 12,
              left: 12,
              child: _VersionBadge(),
            ),
            if (widget.showLegend)
              Positioned(
                left: 12,
                bottom: 12,
                child: _MapLegend(mode: widget.legendMode),
              ),
          ],
        ),
      ),
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

  double get projectedWidth => math.max(0.000001, maxX - minX);
  double get projectedHeight => math.max(0.000001, maxY - minY);
  double get aspectRatio => (projectedWidth / projectedHeight).clamp(0.55, 2.10).toDouble();

  Size fittedCanvasSize(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return const Size(1, 1);

    final ratio = aspectRatio;
    final widthIfFullHeight = viewport.height * ratio;
    if (widthIfFullHeight <= viewport.width) {
      return Size(widthIfFullHeight, viewport.height);
    }
    return Size(viewport.width, viewport.width / ratio);
  }

  factory _ProjectionDomain.fromStreets(
    List<StreetEntry> streets, {
    required GeoBounds fallbackBounds,
  }) {
    final projectedPoints = <Offset>[];

    for (final street in streets) {
      for (final segment in street.segments) {
        for (final rawPoint in segment) {
          final point = _normaliseParisPoint(rawPoint);
          if (_isPlausibleParisPoint(point)) {
            projectedPoints.add(_projectLocalMeters(point));
          }
        }
      }
    }

    if (projectedPoints.length < 2) {
      projectedPoints.addAll([
        _projectLocalMeters(
          GeoPoint(fallbackBounds.minLatitude, fallbackBounds.minLongitude),
        ),
        _projectLocalMeters(
          GeoPoint(fallbackBounds.maxLatitude, fallbackBounds.maxLongitude),
        ),
      ]);
    }

    projectedPoints.sort((a, b) => a.dx.compareTo(b.dx));
    final minX = _percentile(projectedPoints.map((point) => point.dx), 0.002);
    final maxX = _percentile(projectedPoints.map((point) => point.dx), 0.998);
    projectedPoints.sort((a, b) => a.dy.compareTo(b.dy));
    final minY = _percentile(projectedPoints.map((point) => point.dy), 0.002);
    final maxY = _percentile(projectedPoints.map((point) => point.dy), 0.998);

    final width = math.max(1.0, maxX - minX);
    final height = math.max(1.0, maxY - minY);
    final xPadding = width * 0.04;
    final yPadding = height * 0.04;

    return _ProjectionDomain(
      minX: minX - xPadding,
      maxX: maxX + xPadding,
      minY: minY - yPadding,
      maxY: maxY + yPadding,
    );
  }
}

class _MapProjection {
  _MapProjection(this.domain, this.size) {
    const padding = 14.0;
    final availableWidth = math.max(1.0, size.width - padding * 2);
    final availableHeight = math.max(1.0, size.height - padding * 2);

    _scale = math.min(
      availableWidth / domain.projectedWidth,
      availableHeight / domain.projectedHeight,
    );

    final renderedWidth = domain.projectedWidth * _scale;
    final renderedHeight = domain.projectedHeight * _scale;
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
    final projected = _projectLocalMeters(point);
    final x = _offsetX + (projected.dx - domain.minX) * _scale;
    final y = _offsetY + (domain.maxY - projected.dy) * _scale;
    return Offset(x, y);
  }

  GeoPoint toGeo(Offset offset) {
    final projectedX = domain.minX + (offset.dx - _offsetX) / _scale;
    final projectedY = domain.maxY - (offset.dy - _offsetY) / _scale;
    return _unprojectLocalMeters(Offset(projectedX, projectedY));
  }
}

GeoPoint _normaliseParisPoint(GeoPoint point) {
  final looksNormal = point.latitude >= 47.0 &&
      point.latitude <= 50.0 &&
      point.longitude >= 1.0 &&
      point.longitude <= 4.0;
  if (looksNormal) return point;

  final looksSwapped = point.longitude >= 47.0 &&
      point.longitude <= 50.0 &&
      point.latitude >= 1.0 &&
      point.latitude <= 4.0;
  if (looksSwapped) return GeoPoint(point.longitude, point.latitude);

  return point;
}

bool _isPlausibleParisPoint(GeoPoint point) {
  return point.latitude >= 48.75 &&
      point.latitude <= 48.95 &&
      point.longitude >= 2.15 &&
      point.longitude <= 2.55;
}

Offset _projectLocalMeters(GeoPoint point) {
  const originLat = 48.8566;
  const originLon = 2.3522;
  const metersPerDegreeLatitude = 111320.0;
  final originLatRadians = originLat * math.pi / 180.0;
  final metersPerDegreeLongitude = metersPerDegreeLatitude * math.cos(originLatRadians);
  final x = (point.longitude - originLon) * metersPerDegreeLongitude;
  final y = (point.latitude - originLat) * metersPerDegreeLatitude;
  return Offset(x, y);
}

GeoPoint _unprojectLocalMeters(Offset projected) {
  const originLat = 48.8566;
  const originLon = 2.3522;
  const metersPerDegreeLatitude = 111320.0;
  final originLatRadians = originLat * math.pi / 180.0;
  final metersPerDegreeLongitude = metersPerDegreeLatitude * math.cos(originLatRadians);
  final latitude = originLat + projected.dy / metersPerDegreeLatitude;
  final longitude = originLon + projected.dx / metersPerDegreeLongitude;
  return GeoPoint(latitude, longitude);
}

double _percentile(Iterable<double> values, double fraction) {
  final list = values.where((value) => value.isFinite).toList()..sort();
  if (list.isEmpty) return 0;
  final rawIndex = ((list.length - 1) * fraction).round();
  final index = rawIndex.clamp(0, list.length - 1).toInt();
  return list[index];
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
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
        if (segment.length < 2) continue;
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
        ..color = const Color(0xFFB8C0CA).withValues(alpha: 0.42)
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
          ..strokeWidth = 2.8
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
  const _MapLegend({required this.mode});

  final MapLegendMode mode;

  @override
  Widget build(BuildContext context) {
    final text = mode == MapLegendMode.teams
        ? 'Gris : libre\nRouge/Bleu/Vert/Jaune : équipe'
        : 'Gris : à découvrir\nCouleur : rareté trouvée';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6191E27),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Carte V4 · ratio réel · aucun nom',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
