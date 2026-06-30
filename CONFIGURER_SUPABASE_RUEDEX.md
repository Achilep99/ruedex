# Configurer Supabase pour RueDex V3

Cette version ajoute la base en ligne : saisons, équipes, captures et début de profils/clans.

## 1. Créer le projet

1. Va sur Supabase.
2. Crée un nouveau projet.
3. Choisis une région proche de la France si possible.
4. Garde le plan gratuit pour le moment.

## 2. Activer les comptes anonymes

Dans Supabase :

1. Authentication
2. Providers
3. Anonymous Sign-ins
4. Active l'option

RueDex créera un joueur automatiquement au premier lancement.

## 3. Créer les tables

1. Ouvre SQL Editor.
2. Crée une nouvelle requête.
3. Copie le contenu de :

```text
supabase/schema_ruedex.sql
```

4. Clique sur Run.

Le script crée :

- teams
- seasons
- players
- clans
- clan_members
- street_ownership
- scan_events
- la fonction serveur capture_street
- les règles RLS de base

## 4. Récupérer les clés publiques

Dans Supabase :

1. Project Settings
2. API
3. Copie :
   - Project URL
   - anon public key

Ne copie jamais la service_role key dans GitHub ou dans l'application.

## 5. Ajouter les secrets GitHub

Dans ton dépôt GitHub :

1. Settings
2. Secrets and variables
3. Actions
4. New repository secret

Ajoute :

```text
SUPABASE_URL = ton Project URL
SUPABASE_ANON_KEY = ta anon public key
```

## 6. Compiler

Après le prochain Push, GitHub Actions construira les APK en injectant les clés.

Si les secrets sont absents, l'application compile quand même, mais reste en mode local.

## Ce qui marche dans cette première version en ligne

- connexion anonyme ;
- création automatique du joueur ;
- choix d'une équipe ;
- capture d'une rue pour son équipe ;
- couleur de la carte selon l'équipe propriétaire ;
- base préparée pour saisons, profils et clans.

## Ce qui reste volontairement pour plus tard

- vrais profils publics ;
- création/rejoindre un clan ;
- classement ;
- règles complètes de saison ;
- anti-triche avancé ;
- stockage de photos.
