import 'package:flutter_test/flutter_test.dart';
import 'package:ruedex_mvp/models/geo_point.dart';
import 'package:ruedex_mvp/models/street_entry.dart';
import 'package:ruedex_mvp/services/geometry_service.dart';

void main() {
  test('la distance utilise le tronçon entier et pas le centre de la rue', () {
    final street = StreetEntry(
      id: 'longue',
      officialName: 'Rue très longue',
      roadType: 'RUE',
      normalizedName: 'TRES LONGUE',
      aliases: const [],
      city: 'Paris',
      arrondissement: '',
      origin: '',
      rarity: StreetRarity.nonClassee,
      raritySource: 'test',
      segments: const [[GeoPoint(48.8500, 2.3000), GeoPoint(48.8500, 2.3400)]],
    );
    final distance = GeometryService.distanceToStreetMeters(
      const GeoPoint(48.8501, 2.3002),
      street,
    );
    expect(distance, lessThan(30));
  });
}
