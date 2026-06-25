# Obtenir les APK avec GitHub Actions

Le serveur GitHub télécharge la base complète de Paris, installe Flutter, teste RueDex puis compile deux APK.

1. Place le contenu du projet dans ton dépôt GitHub.
2. Vérifie que `.github/workflows/build-apk.yml` est bien présent.
3. Ouvre **Actions** puis **Construire APK RueDex V2**.
4. Utilise **Run workflow** si aucune exécution ne démarre automatiquement.
5. Une fois toutes les étapes vertes, ouvre l'exécution.
6. Dans **Artifacts**, télécharge **RueDex-V2-APK**.
7. Décompresse le ZIP :
   - `RueDex-developpeur.apk` pour les tests ;
   - `RueDex-utilisateur.apk` pour vérifier la vraie expérience joueur.

Les APK sont des builds `debug`, installables directement pour les essais. La publication Play Store demandera ensuite un build `release` signé.
