# Changelog

## [1.0.1] - 2026-10-26

### Ajouts

- Mode lecture inspiré de Joker sur Mac et Windows : vidéo à gauche, panneau timecode/rôles à droite et bande beige en bas. Échap revient à l'éditeur.
- Boucles dans le script, avec indication en rouge de la boucle et des répliques en cours.
- Options de formatage pour l'export RTF : page de garde, croisillé, liste des rôles avec boucles ou premier timecode, script classique ou documentaire, TC Out et filtre par rôle.
- Export MP4 **expérimental** de la présentation du mode lecture : plage de timecodes, 720p/1080p, 24/25/30/60 images/s, son VO/VI ou muet, progression et annulation.

### Corrections et améliorations

- Menus Windows rapprochés de ceux du Mac : import de rôles, export DetX, fichiers récents, suppression des positions et commandes d'édition.
- Meilleure prise en compte du texte sélectionné pour les commandes de presse-papiers Windows.
- Vérification du projet et recherche de mises à jour réunies dans le moteur commun.
- Correction des informations du panneau de lecture Windows lors des changements de texte et défilement des rôles vers le bas.
- Lecture PCM par blocs pour l'export WAV/AIFF, réutilisation des images vidéo sur Windows et alimentation audio/vidéo indépendante sur Mac.
- Version affichée et noms des distributions unifiés ; archives portables et installateurs séparés, sans ZIP supplémentaire dans les artefacts Actions.

### Limites connues

- **L'export MP4 est expérimental et peut rester très lent.** Les performances et la compatibilité doivent encore être validées sur davantage de médias et de machines.
- FFmpeg n'est pas intégré à cette version. L'export utilise AVFoundation sur Mac et Media Foundation sur Windows.
- L'enregistrement microphone et la détection automatique des plans restent à porter sur Windows.
- Windows ARM64, la projection et certains outils du logiciel original nécessitent encore des vérifications ou du travail.

## [1.0.0] - Première version publique

- Première distribution de la réécriture Swift de Cappella, logiciel développé à l'origine par Chinkel.
- Versions macOS Apple Silicon et Windows x64/ARM64.
- Édition sur bande à quatre pistes, fichiers DetX, rôles, synchronisation vidéo, audio VO/VI, recherche et commandes de transport.
