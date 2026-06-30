# RueDex V4 — comptes, équipes, clans et deux cartes

## Avant de pousser la V4

1. Dans Supabase, ouvre **SQL Editor**.
2. Lance le fichier `supabase/schema_ruedex.sql` de cette V4.
3. Dans **Authentication → Sign In / Providers → Email**, pour les tests rapides, désactive la confirmation email si elle bloque l'inscription.
4. Vérifie que les secrets GitHub existent :
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

## Ce que la V4 ajoute

- création de compte email / mot de passe ;
- connexion / déconnexion ;
- pseudo joueur ;
- choix d'équipe verrouillé pour la saison ;
- création de clan ;
- rejoindre un clan avec un tag ;
- clan limité à l'équipe du joueur ;
- carte personnelle : rues découvertes par le joueur, couleurs de rareté ;
- carte de conquête : rues possédées par les équipes, couleurs d'équipe ;
- capture synchronisée serveur : une rue scannée passe à la couleur de l'équipe pour tous les joueurs ;
- Realtime Supabase sur `street_ownership` et `personal_discoveries` ;
- carte corrigée avec un canevas au ratio géographique réel.

## Test à faire

1. Installe l'APK développeur sur un téléphone A.
2. Crée un compte A et choisis l'équipe rouge.
3. Installe l'APK développeur sur un téléphone B, ou réinstalle avec un autre compte.
4. Choisis l'équipe bleue.
5. Sur A, scanne une rue en mode développeur avec GPS manuel + texte simulé.
6. Ouvre la carte de conquête sur B : la rue doit apparaître rouge.
7. Sur B, rescane la même rue : elle doit passer bleue sur les deux téléphones.

Si la carte de conquête ne se met pas en direct, vérifie dans Supabase que Realtime est bien actif sur `street_ownership`.
