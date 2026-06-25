import 'package:flutter/material.dart';

import '../models/street_entry.dart';

Color rarityColor(StreetRarity rarity) => switch (rarity) {
      StreetRarity.nonClassee => const Color(0xFF7A8797),
      StreetRarity.commune => const Color(0xFF45C477),
      StreetRarity.peuCommune => const Color(0xFF4AA3FF),
      StreetRarity.rare => const Color(0xFF9B6BFF),
      StreetRarity.epique => const Color(0xFFFF8D42),
      StreetRarity.legendaire => const Color(0xFFFFD45A),
    };

class RarityBadge extends StatelessWidget {
  const RarityBadge({required this.rarity, super.key});

  final StreetRarity rarity;

  @override
  Widget build(BuildContext context) {
    final color = rarityColor(rarity);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          rarity.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
