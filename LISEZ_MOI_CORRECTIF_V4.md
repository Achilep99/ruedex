# Correctif RueDex V4 — build Paris + realtime Supabase

Ce correctif remplace seulement 3 fichiers :

- `tools/build_paris_database.py`
- `lib/services/online_game_service.dart`
- `lib/screens/paris_map_screen.dart`

Corrections :

1. Le générateur Paris lit maintenant les exports JSON même si OpenData Paris les renvoie compressés en gzip.
2. Le flux Supabase Realtime ne chaîné plus `.eq(...)` après `.stream(...)`, car cette API n'existe pas dans la version installée. Le filtrage se fait dans le `map`, donc la carte de conquête reçoit bien les mises à jour.
3. Les deux `if` sans accolades dans `paris_map_screen.dart` sont corrigés.

Procédure : copier `lib` et `tools` dans `ruedex_mvp`, accepter les remplacements, commit puis push.
