import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/street_entry.dart';

class StreetRepository {
  Future<List<StreetEntry>> loadStreets() async {
    final rawJson = await rootBundle.loadString('assets/data/streets.json');
    final decoded = jsonDecode(rawJson) as List<dynamic>;

    return decoded
        .map((item) => StreetEntry.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
