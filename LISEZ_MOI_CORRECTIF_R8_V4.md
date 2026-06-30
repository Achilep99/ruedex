# Correctif RueDex V4 - R8 / ML Kit release

Ce correctif règle l'erreur Android release :

```text
Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
Execution failed for task ':app:minifyReleaseWithR8'
```

Il fait deux choses pendant la configuration Android GitHub Actions :

1. force la release Android sans minification R8 si le projet généré l'active ;
2. ajoute explicitement les dépendances ML Kit pour les scripts chinois, devanagari, japonais et coréen, car le plugin Flutter les référence même si RueDex utilise surtout le latin.

## Installation

1. Copier les dossiers `.github` et `tools` dans `ruedex_mvp`.
2. Accepter les remplacements.
3. Commit : `Correctif R8 ML Kit V4`
4. Push.
5. Relancer/attendre GitHub Actions.

Ce correctif ne modifie pas Supabase, les comptes, les clans, les cartes ou le scanner.
