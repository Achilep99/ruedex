# RueDex V4.2 — clans, scores, chat, carte et captures serveur

## À faire dans Supabase avant de tester

1. Ouvre Supabase > SQL Editor > New query.
2. Copie-colle tout le fichier :
   `supabase/schema_ruedex.sql`
3. Clique sur Run.

Ce script est idempotent : il peut être relancé. Il ajoute :

- collection personnelle liée au compte Supabase ;
- scores joueur : collection, conquête, clan ;
- score brut de clan ;
- prérequis de clan en nombre de rues découvertes ;
- chat de clan ;
- signalement de message ;
- nettoyage automatique des vieux messages non signalés ;
- journal de clan limité aux paliers importants ;
- fonction serveur de capture complète.

## Ce qui doit fonctionner

- Une rue découverte par un joueur A ne doit plus apparaître dans la collection du joueur B sur le même téléphone.
- Toute capture validée en ligne appelle Supabase et met à jour :
  - personal_discoveries ;
  - street_ownership ;
  - player_scores ;
  - score du clan si le joueur est membre d'un clan.
- Une rue déjà découverte personnellement peut être reprise pour son équipe.
- Les meilleurs clans sont visibles directement.
- La recherche de clan fonctionne par début de nom ou de tag.
- Le chef peut expulser un membre.
- Les clans restent liés à une seule équipe.
- Les messages signalés sont conservés.
- La carte de conquête possède des filtres par couleur et pour les rues non capturées.
- Toucher une rue affiche son nom seulement si elle est déjà découverte personnellement.
- Le bouton itinéraire ouvre une application de carte externe uniquement pour une rue découverte.

## Note

La carte utilise désormais un ratio Paris fixe plutôt qu'une boîte calculée depuis les données, pour éviter l'écrasement horizontal/vertical.
