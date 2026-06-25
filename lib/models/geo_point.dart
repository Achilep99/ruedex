import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(List<dynamic> json) => GeoPoint(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
      );

  List<double> toJson() => [latitude, longitude];
}

class GeoBounds {
  const GeoBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  factory GeoBounds.fromPoints(Iterable<GeoPoint> points) {
    var minLat = double.infinity;
    var maxLat = double.negativeInfinity;
    var minLon = double.infinity;
    var maxLon = double.negativeInfinity;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLon = math.min(minLon, point.longitude);
      maxLon = math.max(maxLon, point.longitude);
    }
    if (!minLat.isFinite) {
      return const GeoBounds(
        minLatitude: 48.815,
        maxLatitude: 48.905,
        minLongitude: 2.225,
        maxLongitude: 2.475,
      );
    }
    return GeoBounds(
      minLatitude: minLat,
      maxLatitude: maxLat,
      minLongitude: minLon,
      maxLongitude: maxLon,
    );
  }

  GeoBounds padded(double latitudePadding, double longitudePadding) => GeoBounds(
        minLatitude: minLatitude - latitudePadding,
        maxLatitude: maxLatitude + latitudePadding,
        minLongitude: minLongitude - longitudePadding,
        maxLongitude: maxLongitude + longitudePadding,
      );

  bool containsRoughly(GeoPoint point, double radiusMeters) {
    final latMargin = radiusMeters / 111320;
    final lonScale = math.cos(point.latitude * math.pi / 180).abs().clamp(0.2, 1.0).toDouble();
    final lonMargin = radiusMeters / (111320 * lonScale);
    return point.latitude >= minLatitude - latMargin &&
        point.latitude <= maxLatitude + latMargin &&
        point.longitude >= minLongitude - lonMargin &&
        point.longitude <= maxLongitude + lonMargin;
  }
}
