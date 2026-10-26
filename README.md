<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="packaging/Resources/CappellaLogo_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="packaging/Resources/CappellaLogo.png">
    <img src="packaging/Resources/CappellaLogo.png" alt="Logo Cappella" width="240">
  </picture>
</p>

<h1 align="center">Cappella</h1>

<p align="center">
  Réécriture en Swift pour macOS et Windows du logiciel de bande rythmo développé par Chinkel.
</p>

<p align="center">
  <a href="https://github.com/BUCHMULLER-Nassim-2326028b/CappellaSwift/releases">Télécharger</a>
  · <a href="CHANGELOG.md">Changelog</a>
  · <a href="#roadmap">Roadmap</a>
  · <a href="#ce-qui-reste-à-faire">Ce qui reste à faire</a>
  · <a href="docs/RELEASES.md">Créer une release</a>
</p>

## Le projet

**Cappella a été développé à l'origine par Chinkel** pour le travail de doublage.
Il permet d'écrire et de synchroniser les dialogues avec une vidéo sur une bande rythmo.

Cette réécriture est réalisée par nvssgoat sans le code source original (donc du clean room).
Un travail de recherche puis reproduction des fonctions, de l'interface et des raccourcis
a été effectué. Ensuite viendront les améliorations : UI, fluidité, édition
et nouveaux outils, gardant la compatibilité avec les projets DetX de l'original.

Les nouveautés de la version **1.0.1** sont détaillées dans le [changelog](CHANGELOG.md).

Des fonctions manquent encore et certains comportements restent à comparer avec l'original.
*(problème connu : il manque la feature de déplacement de plans)*

A terme, cette nouvelle version de Cappella n'aura pas simplement l'ambition d'être un simple
portage moderne mais bien une continuation avec de nouvelles fonctionnalités et des améliorations
QoL.

## Origine du projet

L'idée de porter Cappella en Swift m'est venu de la nécessité d'un ami à utiliser le logiciel
Cappella sur son MacBook Pro M5. La version publique de Cappella n'ayant pas été maintenue depuis
près de 20 ans et les technologies de virtualisation (WineHQ, etc...) n'étant pas top sur Apple Silicon,
j'ai alors décidé de porter le logiciel sur Mac.

La version Windows est également écrite en Swift. Le projet ayant commencé comme un simple portage Mac,
ce backport Windows a été réfléchi et effectué secondairement.

## Plateformes et téléchargements

| Plateforme | Architecture | Distribution |
|---|---|---|
| macOS | Apple Silicon (ARM64) | ZIP contenant Cappella.app |
| Windows | Intel / AMD (x64) | ZIP portable et installateur EXE |
| Windows | ARM64 | ZIP portable et installateur EXE ; validation encore en cours |

Les versions publiées se trouvent dans les [releases GitHub](https://github.com/BUCHMULLER-Nassim-2326028b/CappellaSwift/releases).
Les builds de développement sont disponibles dans les artefacts de GitHub Actions.
Les fichiers portent le même numéro de version que l'application :

~~~text
Cappella-VERSION-macOS-arm64-Portable.zip
Cappella-VERSION-Windows-x64-Portable.zip
Cappella-VERSION-Windows-x64-Setup.exe
Cappella-VERSION-Windows-arm64-Portable.zip
Cappella-VERSION-Windows-arm64-Setup.exe
~~~

Sur Windows, le **Setup** installe Cappella et le Windows App Runtime 1.7 de la bonne
architecture si nécessaire. Le **portable** s'extrait dans un dossier ; il nécessite
ce runtime installé séparément. Sur Mac, extraire le ZIP et déplacer Cappella.app
dans Applications.

## Fonctions disponibles

- Script synchronisé avec la rythmo, titres de boucle et texte rouge pour les répliques et la boucle en cours.
- Vidéo, timecode et bande à quatre pistes, avec panneaux redimensionnables et thèmes clair/sombre.
- Édition des dialogues au clic simple, sélection du rôle, portraits et menus contextuels.
- Signes de synchronisation, boucles, plans, zoom et défilement horizontal.
- Lecture avant et arrière, jog, shuttle, audio séparé et commutation VO/VI.
- Recherche dans les dialogues, avec filtre par rôle, casse et mots entiers.
- Lecture et écriture DetX, format de travail .cappellaproject et sauvegarde automatique désactivable.
- Préférences enregistrées, choix des polices système et mode vidéo pleine fenêtre.
- Mode lecture inspiré de Joker : vidéo, panneau timecode/rôles et bande beige.
- Export **expérimental** de cette présentation en MP4, avec plage de timecodes, cadence, définition et son VO/VI.
- Export du script en RTF : page de garde, croisillé, liste des rôles, présentation classique ou documentaire, TC Out et filtre par rôle.
- Remplacement du projet courant avec demande d'enregistrement et ouverture de plusieurs instances.

## Nouveautés de la 1.0.1

Le **mode lecture**, accessible dans Affichage, reprend une présentation inspirée
de Joker : vidéo à gauche, timecode et rôles à droite, bande beige en bas.
Échap revient à l'éditeur. Les boucles apparaissent aussi dans le script de gauche,
avec la même indication de lecture que les répliques.

L'export de script propose maintenant le formatage du document. Les menus Windows
reprennent davantage de commandes du Mac, notamment l'import de rôles, les fichiers
récents et la gestion des positions.

### Export MP4 expérimental

**Fichier > Exporter > Rythmo MP4** exporte la présentation du mode lecture en
720p ou 1080p, à 24, 25, 30 ou 60 images/s, sur une plage de timecodes et avec le son
VO, VI ou sans son. La progression et l'annulation sont disponibles.

Cet export peut être très lent, y compris avec l'accélération matérielle demandée.
Les performances et la compatibilité avec les différents médias restent à valider.
La 1.0.1 utilise les encodeurs natifs de Windows et macOS. **FFmpeg n'est pas encore
intégré** ; une évolution du moteur d'export est prévue.

## Ce qui reste à faire

| Sujet | Travail restant |
|---|---|
| Parité Mac / Windows | Porter l'enregistrement microphone et la détection automatique des plans sur Windows, compléter la projection. |
| Audio et vidéo | Vérifier les codecs et les dispositions multicanales sur davantage de médias. |
| Export MP4 expérimental | Accélérer le rendu et l’encodage, étudier FFmpeg et valider davantage de médias sur Mac et Windows. |
| Anciens projets | Tester davantage de variantes DetX, les anciens .det et la réouverture des exports dans le logiciel original. |
| Outils métier | Compléter Orphée/FTDI, le sous-titrage UER et l'impression. |
| Lecture inverse | Vérifier la synchronisation avec différents codecs ; la première préparation du son demande encore du temps. |
| Rendu et saisie | Comparer la typographie, la sélection et la fluidité sur des projets longs et différents écrans. |
| Distribution | Terminer la validation Windows ARM64 et de l'installation, puis préparer la signature Windows et la notarisation Mac. |

Les détails sont dans [Architecture](docs/ARCHITECTURE.md) et [Windows](docs/WINDOWS.md).

## Roadmap

~~~mermaid
flowchart LR
    A["1. Réécriture native<br/>Swift et moteur DetX<br/>Interfaces Mac et Windows"]
    B["2. Portage des fonctions<br/>Bande rythmo, saisie<br/>Menus et audio"]
    C["3. Parité et corrections<br/>Formats et outils métier<br/>Tests en séance"]
    D["4. Distribution<br/>Installateurs et ARM64<br/>Signature et notarisation"]
    E["5. Améliorations<br/>Faire évoluer Cappella<br/>À partir des retours d'utilisation"]

    A --> B --> C --> D --> E
~~~

Le portage des fonctions et les corrections sont en cours. L'objectif final est
aussi d'améliorer le logiciel, une fois les usages de l'original couverts.

## Compiler

Le moteur CappellaCore est partagé entre les deux versions. L'interface Mac utilise
SwiftUI et AppKit ; l'interface Windows utilise WinUI 3 avec Swift-WinRT.

### macOS ARM64

Sur un Mac Apple Silicon avec les outils de développement Apple :

~~~bash
bash scripts/build-macos.sh
open dist/Cappella.app
~~~

La cible minimale est macOS 13. Les workflows vérifient l'ouverture sur macOS 15
et 26. La signature actuelle est ad hoc.

### Windows x64 et ARM64

Installer Swift pour Windows, les outils C++ de Visual Studio et le Windows SDK
pour l'architecture cible :

~~~powershell
.\scripts\build-windows.ps1 -Architecture x64
~~~

Pour les compilations suivantes, réutiliser les projections WinRT :

~~~powershell
.\scripts\build-windows.ps1 -SkipPrepare -Architecture x64
~~~

Remplacer x64 par arm64 avec une chaîne de compilation ARM64. GitHub Actions
utilise des runners natifs pour les deux architectures.

Pour créer le Setup, installer Inno Setup 6 puis lancer :

~~~powershell
.\scripts\build-windows-installer.ps1 -Architecture x64
~~~

Les builds sont en release par défaut. Ajouter -Configuration debug pour le
développement. Les prérequis complets sont dans [Windows](docs/WINDOWS.md),
et la publication est décrite dans [Créer une release](docs/RELEASES.md).

## Utilisation de l'IA

L'assistance d'un modèle de langage IA (LLM) a été précieuse dans le portage de l'application.
Les vérifications automatiques et les retours d'utilisation servent à corriger les régressions.
Certaines fonctions, notamment l'export MP4, restent expérimentales.

## Retours et contributions

Pour signaler un bug, préciser la plateforme, la version et les étapes pour le
reproduire. Un petit DetX d'exemple et une capture du comportement attendu dans
l'original sont utiles. Éviter de joindre des médias confidentiels.

- [Issues GitHub](https://github.com/BUCHMULLER-Nassim-2326028b/CappellaSwift/issues)
- [Architecture et limites](docs/ARCHITECTURE.md)
- [Raccourcis](docs/RACCOURCIS.md)
- [Scripts et vérifications CI](docs/SCRIPTS.md)
- [Références du logiciel original](docs/reference/README.md)
