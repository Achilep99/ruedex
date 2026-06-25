import 'dart:math' as math;

import '../models/geo_point.dart';
import '../models/street_entry.dart';

class GeometryService {
  const GeometryService._();

  static double distanceToStreetMeters(GeoPoint point, StreetEntry street) {
    var best = double.infinity;
    for (final segment in street.segments) {
      if (segment.length < 2) {
        continue;
      }
      for (var index = 0; index < segment.length - 1; index++) {
        final distance = distanceToSegmentMeters(point, segment[index], segment[index + 1]);
        if (distance < best) {
          best = distance;
        }
      }
    }
    return best;
  }

  static double distanceToSegmentMeters(GeoPoint point, GeoPoint start, GeoPoint end) {
    final latitudeReference = point.latitude * math.pi / 180;
    final metersPerLongitude = 111320 * math.cos(latitudeReference);
    const metersPerLatitude = 111320.0;

    final px = (point.longitude - start.longitude) * metersPerLongitude;
    final py = (point.latitude - start.latitude) * metersPerLatitude;
    final sx = (end.longitude - start.longitude) * metersPerLongitude;
    final sy = (end.latitude - start.latitude) * metersPerLatitude;
    final lengthSquared = sx * sx + sy * sy;
    if (lengthSquared == 0) {
      return math.sqrt(px * px + py * py);
    }

    final projection = ((px * sx + py * sy) / lengthSquared).clamp(0.0, 1.0).toDouble();
    final dx = px - projection * sx;
    final dy = py - projection * sy;
    return math.sqrt(dx * dx + dy * dy);
  }
}
