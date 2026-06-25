# RueDex — MVP Android

Prototype jouable pour photographier une plaque de rue, lire son texte avec OCR, utiliser le GPS comme filtre et ajouter la rue à une collection locale.

## Ce qui fonctionne déjà

- Photo avec la caméra ou import depuis la galerie.
- OCR latin avec Google ML Kit.
- Vrai GPS ou coordonnées simulées.
- Correction d'erreurs OCR courantes, par exemple `VICT0R HUG0`.
- Classement des rues candidates par score texte + distance.
- Validation automatique au-dessus d'un seuil.
- Validation forcée dans le mode développeur.
- RueDex local avec fiches, raretés et remise à zéro.
- Tests automatisés de normalisation et de correspondance.

## Installation sur Windows 10/11

### 1. Installer Flutter

Installe Flutter stable et ajoute le dossier `flutter\bin` au PATH Windows.

Dans PowerShell, vérifie ensuite :

```powershell
flutter --version
flutter doctor
```

### 2. Installer Android Studio

Dans Android Studio, installe :

- Android SDK ;
- Android SDK Platform 35 ou plus récente ;
- Android Emulator ;
- Android SDK Command-line Tools.

Crée ensuite un appareil virtuel Android 64 bits dans **Device Manager**, puis démarre-le.

Accepte les licences si nécessaire :

```powershell
flutter doctor --android-licenses
```

### 3. Préparer RueDex

Double-clique sur :

```text
PREPARER_PROJET_WINDOWS.bat
```

Le script génère automatiquement la partie Android compatible avec la version de Flutter installée, remet le code RueDex en place, ajoute les permissions GPS et télécharge les dépendances.

### 4. Lancer l'application

Avec l'émulateur ouvert, double-clique sur :

```text
LANCER_APPLICATION.bat
```

## Premier test sans aucune photo

1. Ouvre **Scanner une plaque**.
2. Laisse le mode **Dev** activé.
3. Le texte simulé contient déjà `RUE VICT0R HUG0`.
4. Les coordonnées correspondent à l'entrée de démonstration Victor Hugo.
5. Appuie sur **Tester la reconnaissance**.
6. Sélectionne le premier candidat et valide la découverte.
7. Reviens dans le RueDex.

## Test avec une vraie photo

Dans l'émulateur, utilise **Galerie** pour importer une photo de plaque depuis le stockage virtuel. Sur un téléphone Android branché en USB, les boutons **Caméra** et **Vrai GPS** permettent un test réel.

Pour lancer sur un téléphone :

1. Active les options développeur et le débogage USB.
2. Branche le téléphone.
3. Vérifie qu'il apparaît avec `flutter devices`.
4. Lance `LANCER_APPLICATION.bat`.

## Modifier la base de rues

Le fichier est ici :

```text
assets/data/streets.json
```

Chaque entrée contient :

```json
{
  "id": "identifiant_unique",
  "officialName": "Avenue Victor-Hugo",
  "aliases": ["Avenue Victor Hugo", "Victor Hugo"],
  "city": "Paris",
  "latitude": 48.8706,
  "longitude": 2.2854,
  "subjectName": "Victor Hugo",
  "summary": "Courte biographie vérifiée.",
  "rarity": "commune"
}
```

Raretés possibles : `commune`, `peuCommune`, `rare`, `epique`, `legendaire`.

Les coordonnées incluses servent uniquement à la démonstration technique. Pour une version publique, il faudra représenter les rues par plusieurs points ou segments plutôt que par un seul point central.

## Lancer les tests

Double-clique sur :

```text
TESTER_CODE.bat
```

## Limites volontaires de ce MVP

- Android uniquement pour l'instant.
- Analyse après capture, pas encore OCR vidéo en temps réel.
- Petite base JSON locale de démonstration.
- Une seule coordonnée par rue.
- Les fiches historiques doivent être vérifiées avant publication.
- Pas encore de compte, serveur, carte, classement ou synchronisation cloud.

## Prochaine évolution logique

La prochaine étape est de tester le moteur avec un dossier de vraies photos de plaques. On pourra ensuite ajuster les seuils, ajouter le recadrage automatique de la plaque et remplacer la base de démonstration par les rues d'une ville pilote.
