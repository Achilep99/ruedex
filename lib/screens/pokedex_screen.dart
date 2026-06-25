import 'package:flutter/material.dart';

import '../models/street_entry.dart';
import '../services/discovery_store.dart';
import '../widgets/rarity_badge.dart';

class PokedexScreen extends StatefulWidget {
  const PokedexScreen({
    required this.streets,
    required this.discoveryStore,
    required this.developerMode,
    super.key,
  });

  final List<StreetEntry> streets;
  final DiscoveryStore discoveryStore;
  final bool developerMode;

  @override
  State<PokedexScreen> createState() => _PokedexScreenState();
}

class _PokedexScreenState extends State<PokedexScreen> {
  Set<String> _discoveredIds = const {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await widget.discoveryStore.loadDiscoveredIds();
    if (mounted) setState(() {
      => _discoveredIds = ids);
    }
  }

  Future<void> _reset() async {
    await widget.discoveryStore.clear();
    await _load();
  }

  Future<void> _showDetails(StreetEntry street, bool discovered) async {
    final date = discovered ? await widget.discoveryStore.discoveryDate(street.id) : null;
    if (!mounted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              discovered ? street.officialName : 'Rue non découverte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (discovered) ...[
              RarityBadge(rarity: street.rarity),
              if (street.arrondissement.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(street.arrondissement),
              ],
              if (date != null) ...[
                const SizedBox(height: 8),
                Text('Découverte le ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
              ],
              if (street.hasVerifiedOrigin) ...[
                const SizedBox(height: 18),
                Text('Origine officielle du nom', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(street.origin),
              ],
            ] else
              const Text('Scanne la plaque correspondante pour révéler cette fiche.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.streets.where((street) {
      if (_query.isEmpty) {
        return true;
      }
      if (!widget.developerMode && !_discoveredIds.contains(street.id)) {
        return false;
      }
      return street.officialName.toLowerCase().contains(_query.toLowerCase());
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon RueDex'),
        actions: [
          if (widget.developerMode)
            IconButton(
              tooltip: 'Réinitialiser les découvertes',
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher dans les rues découvertes',
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.88,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final street = visible[index];
                final discovered = _discoveredIds.contains(street.id);
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _showDetails(street, discovered),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: discovered
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(discovered ? Icons.signpost_outlined : Icons.lock_outline, size: 34),
                        const Spacer(),
                        Text(
                          discovered ? street.officialName : '???',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(discovered ? street.rarity.label : 'À découvrir'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
