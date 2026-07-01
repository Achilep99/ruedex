# RueDex V4.3 — réglages clan et carte affinée

## À faire dans Supabase

Avant de compiler l'APK, relancer le script complet :

```text
Supabase → SQL Editor → New query → coller supabase/schema_ruedex.sql → Run
```

Cette version ajoute la fonction serveur `update_clan_settings`, utilisée par le chef pour modifier le nombre minimum de rues découvertes avant de rejoindre le clan.

## Changements principaux

- Ajout d'un bouton **Paramètres du clan** visible uniquement par le chef.
- Le chef peut modifier le prérequis de rues personnelles minimum.
- La recherche de clan continue de fonctionner par début de nom ou tag.
- Les meilleurs clans restent affichés directement.
- Les filtres de carte de conquête passent dans un panneau repliable en bas.
- Le bouton retour n'est plus gêné par les filtres.
- Les rues sont beaucoup plus fines.
- Le zoom maximum passe à x28.
- La sélection d'une rue devient plus précise quand on zoome.
- La légende conquête est masquée pour réduire la surcharge visuelle.

## Fichiers modifiés

```text
lib/screens/clan_screen.dart
lib/screens/paris_map_screen.dart
lib/services/online_game_service.dart
lib/widgets/paris_street_map.dart
supabase/schema_ruedex.sql
```
