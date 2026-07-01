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
    this.visibleTeamIds = const {'red', 'blue', 'green', 'yellow'},
    this.showUnownedStreets = true,
    this.onPointSelected,
    this.onStreetTap,
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
  final Set<String> visibleTeamIds;
  final bool showUnownedStreets;
  final ValueChanged<GeoPoint>? onPointSelected;
  final ValueChanged<StreetEntry>? onStreetTap;
  final bool showLegend;
  final MapLegendMode legendMode;

  @override
  State<ParisStreetMap> createState() => _ParisStreetMapState();
}

class _ParisStreetMapState extends State<ParisStreetMap> {
  final TransformationController _transformationController = TransformationController();

  late _ProjectionDomain _domain;

  @override
  void initState() {
    super.initState();
    _domain = _ProjectionDomain.paris();
  }

  @override
  void didUpdateWidget(covariant ParisStreetMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bounds != widget.bounds) {
      _domain = _ProjectionDomain.paris();
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
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  final canvasSize = _domain.fittedCanvasSize(viewport);
                  final projection = _MapProjection(_domain, canvasSize);

                  return InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1,
                    maxScale: 28,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(900),
                    child: SizedBox(
                      width: viewport.width,
                      height: viewport.height,
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            final street = widget.onStreetTap == null
                                ? null
                                : _nearestVisibleStreet(
                                    details.localPosition,
                                    projection,
                                    maxDistancePx: ((16 / _transformationController.value.getMaxScaleOnAxis()).clamp(2.2, 16.0) as num).toDouble(),
                                  );
                            if (street != null) {
                              widget.onStreetTap!(street);
                              return;
                            }
                            if (widget.onPointSelected != null) {
                              widget.onPointSelected!(projection.toGeo(details.localPosition));
                            }
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
                              visibleTeamIds: widget.visibleTeamIds,
                              showUnownedStreets: widget.showUnownedStreets,
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

  StreetEntry? _nearestVisibleStreet(
    Offset tap,
    _MapProjection projection, {
    required double maxDistancePx,
  }) {
    StreetEntry? best;
    var bestDistance = maxDistancePx;

    for (final street in widget.streets) {
      if (!_streetIsVisible(street)) continue;
      for (final segment in street.segments) {
        if (segment.length < 2) continue;
        for (var index = 0; index < segment.length - 1; index++) {
          final a = projection.toOffset(segment[index]);
          final b = projection.toOffset(segment[index + 1]);
          final distance = _distanceToSegment(tap, a, b);
          if (distance < bestDistance) {
            bestDistance = distance;
            best = street;
          }
        }
      }
    }

    return best;
  }

  bool _streetIsVisible(StreetEntry street) {
    final teamId = widget.teamOwnership[street.id];
    if (teamId != null) return widget.visibleTeamIds.contains(teamId);
    if (widget.teamOwnership.isNotEmpty) return widget.showUnownedStreets;
    if (widget.discoveredIds.contains(street.id)) return true;
    return widget.showUnownedStreets;
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

  double get aspectRatio => projectedWidth / projectedHeight;

  factory _ProjectionDomain.paris() {
    const southWest = GeoPoint(48.805, 2.205);
    const northEast = GeoPoint(48.915, 2.490);
    final a = _projectLocalMeters(southWest);
    final b = _projectLocalMeters(northEast);
    return _ProjectionDomain(
      minX: math.min(a.dx, b.dx),
      maxX: math.max(a.dx, b.dx),
      minY: math.min(a.dy, b.dy),
      maxY: math.max(a.dy, b.dy),
    );
  }

  Size fittedCanvasSize(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return const Size(1, 1);

    final ratio = aspectRatio;
    final heightFromWidth = viewport.width / ratio;
    if (heightFromWidth <= viewport.height) {
      return Size(viewport.width, heightFromWidth);
    }
    return Size(viewport.height * ratio, viewport.height);
  }
}

class _MapProjection {
  _MapProjection(this.domain, this.size) {
    const padding = 18.0;
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

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  final abLengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (abLengthSquared <= 0) return (point - a).distance;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLengthSquared).clamp(0.0, 1.0);
  final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (point - closest).distance;
}

class _ParisStreetPainter extends CustomPainter {
  const _ParisStreetPainter({
    required this.streets,
    required this.projection,
    required this.discoveredIds,
    required this.selectedPoint,
    required this.teamOwnership,
    required this.teamColorResolver,
    required this.visibleTeamIds,
    required this.showUnownedStreets,
  });

  final List<StreetEntry> streets;
  final _MapProjection projection;
  final Set<String> discoveredIds;
  final GeoPoint? selectedPoint;
  final Map<String, String> teamOwnership;
  final Color? Function(String? teamId)? teamColorResolver;
  final Set<String> visibleTeamIds;
  final bool showUnownedStreets;

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
      if (teamId != null && !visibleTeamIds.contains(teamId)) continue;
      if (teamId == null && !showUnownedStreets && !discoveredIds.contains(street.id)) {
        continue;
      }

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
        ..color = const Color(0xFFB8C0CA).withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.22
        ..strokeCap = StrokeCap.round,
    );

    for (final entry in rarityPaths.entries) {
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = rarityColor(entry.key)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
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
          ..strokeWidth = 1.15
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
        oldDelegate.projection.size != projection.size ||
        oldDelegate.visibleTeamIds != visibleTeamIds ||
        oldDelegate.showUnownedStreets != showUnownedStreets;
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.mode});

  final MapLegendMode mode;

  @override
  Widget build(BuildContext context) {
    final text = mode == MapLegendMode.teams
        ? 'Filtres en haut · gris : libre'
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
          'Carte V4.3 · rues fines · zoom x28',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
