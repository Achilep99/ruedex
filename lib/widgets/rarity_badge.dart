import 'package:flutter/material.dart';

import '../models/street_entry.dart';

class RarityBadge extends StatelessWidget {
  const RarityBadge({required this.rarity, super.key});

  final StreetRarity rarity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${'★' * rarity.stars} ${rarity.label}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
