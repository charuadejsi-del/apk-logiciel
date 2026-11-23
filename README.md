# Broderie — prototype (phase 0)

Application Flutter (Android + Windows) de conception et de retouche de fichiers pour machines à broder.
Branche indépendante du dépôt : elle ne partage aucun code avec Monazir.

## Phase 0 — moteur de fichiers
- Lecture : DST (Tajima), PES et PEC (Brother).
- Export : DST.
- Affichage par couleur, zoom, simulation point par point.
- Infos : nombre de points, taille en mm, couleurs, sauts, coupes, temps estimé.
- Retouche : suppression des petits points (seuil 0,3 à 0,6 mm).

## Structure
- `lib/core/` : moteur indépendant de l'interface (`pattern`, `dst`, `pes`, `edits`, `formats`, `demo`).
- `lib/ui/` : écrans Flutter.
- `test/` : tests du moteur (aller-retour DST, décodage PEC, petits points).

Chaque push sur `broderie` compile l'APK et la version Windows et publie une pré-release GitHub.
