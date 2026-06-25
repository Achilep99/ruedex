# RueDex V2 — Paris

Prototype Android d'un jeu de piste : le joueur ouvre le scanner, cadre une plaque de rue et l'application combine automatiquement la caméra, l'OCR et le GPS pour tenter de débloquer une voie de Paris.

## Ce que contient cette version

- scan automatique sans bouton photo ;
- GPS réel récupéré dès l'ouverture du scanner ;
- comparaison OCR qui ignore les mots génériques (`rue`, `avenue`, etc.) ;
- validation seulement si le nom significatif est suffisamment complet ;
- distance calculée vers les tronçons de la rue, et non vers un point central ;
- filtre visuel provisoire : forme allongée, bords probables, fond homogène, contraste et netteté ;
- confirmation du même résultat sur deux images successives ;
- une seule rue validée par session ;
- carte de Paris sans aucun nom : rues inconnues gris clair, rues découvertes colorées ;
- origine officielle du nom affichée uniquement lorsqu'elle existe dans Paris Data ;
- mode développeur avec import d'image, texte OCR simulé, diagnostics et GPS choisi sur la carte ;
- APK utilisateur séparé, compilé sans les outils développeur.

## Base complète de Paris

Le dépôt contient une petite base de secours pour permettre l'ouverture du projet. Pendant GitHub Actions, le workflow télécharge automatiquement :

- la nomenclature officielle des voies de Paris ;
- les tronçons géographiques des voies.

Le script `tools/build_paris_database.py` les fusionne et génère `assets/data/paris_streets.json`. Le build échoue volontairement si moins de 3 000 voies sont produites : cela évite de générer silencieusement un APK avec une base incomplète.

## Les deux APK produits

Dans l'artefact GitHub **RueDex-V2-APK** :

- `RueDex-developpeur.apk` : permet d'activer/désactiver les outils de test. Quand ils sont désactivés, l'écran visible est le mode joueur. Pour rouvrir les réglages, maintiens le titre **RueDex** appuyé.
- `RueDex-utilisateur.apk` : vraie version joueur ; les outils développeur ne sont pas compilés dans l'application.

## Compiler avec GitHub Actions

1. Envoie ce projet sur la branche `main` de ton dépôt GitHub.
2. Ouvre l'onglet **Actions**.
3. Lance ou ouvre **Construire APK RueDex V2**.
4. Quand le workflow est vert, télécharge l'artefact **RueDex-V2-APK**.
5. Décompresse-le puis installe l'APK souhaité.

## Rareté

L'architecture gère les niveaux `commune`, `peuCommune`, `rare`, `epique` et `legendaire`. Quelques voies de démonstration ont un classement manuel dans `assets/data/rarity_overrides.json`.

La majorité des voies reste volontairement **non classée** dans cette version : un classement sérieux doit être calculé à partir d'une base nationale de dénominations, pas inventé à partir de la longueur de la rue ou de la célébrité supposée de la personne. Le futur pipeline de rareté pourra remplir le même champ sans modifier l'application.

## Description et homonymes

RueDex n'essaie pas de deviner une personne depuis le seul nom OCR. La description provient du champ officiel d'origine attaché à l'identifiant exact de la voie parisienne. Si ce champ est vide, aucune description n'est affichée.

## Limites connues

- Le filtre de plaque est heuristique, pas encore un modèle d'IA entraîné.
- Une photo de plaque affichée sur un écran peut encore tromper le filtre ; le GPS et la stabilité sur plusieurs images limitent néanmoins les faux positifs.
- Les seuils de netteté, de cadre et d'OCR devront être ajustés avec de vraies photos variées.
- Le projet n'a pas encore de compte en ligne ni de synchronisation.

## Données et licence

Données géographiques et historiques : Ville de Paris — Paris Data — ODbL. Le code de l'application reste séparé de la base dérivée.
