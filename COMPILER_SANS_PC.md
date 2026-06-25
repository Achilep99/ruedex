# Compiler RueDex sans ordinateur

Cette méthode utilise GitHub Actions : le serveur GitHub installe Flutter, construit l'application, puis fournit l'APK à télécharger.

## Depuis un téléphone Android

1. Crée un compte sur GitHub si nécessaire.
2. Crée un nouveau dépôt vide nommé `ruedex`.
3. Décompresse `ruedex_mvp.zip` sur le téléphone.
4. Depuis le site GitHub en mode navigateur, ajoute le contenu décompressé au dépôt. Le fichier caché `.github/workflows/build-apk.yml` doit impérativement être inclus.
5. Ouvre l'onglet **Actions** du dépôt.
6. Ouvre **Construire APK RueDex**.
7. Appuie sur **Run workflow**, puis confirme.
8. Quand le build est terminé, ouvre son résultat et télécharge l'artefact **RueDex-APK**.
9. Décompresse l'artefact et installe `app-debug.apk`.

Android peut demander l'autorisation « Installer des applications inconnues » pour ton navigateur ou ton gestionnaire de fichiers.

## Important

L'APK généré est une version de test (`debug`). Elle est suffisante pour installer et essayer RueDex sur ton téléphone. Une future publication sur le Play Store demandera une version `release` signée.
