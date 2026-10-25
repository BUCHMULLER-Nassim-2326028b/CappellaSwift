# Architecture

## Modules

| Dossier | Responsabilité |
|---|---|
| Sources/CappellaCore | Modèle, DetX, édition et brouillons, historique, sauvegardes, recherche, navigation, préparation PCM, routage VO/VI et préférences |
| Sources/CappellaSession | Session Mac, remplacement/enregistrement des documents, événements Finder et adaptation des menus AppKit |
| Sources/CappellaMac | Interface SwiftUI/AppKit, transport AVFoundation, édition sur bande, projection, enregistrement et analyse des plans |
| Sources/CappellaWindows | Interface WinUI 3, document Windows, transport multimédia et édition sur bande |
| Sources/CWindowsInterop | Rattachement des sélecteurs à la fenêtre et décodage audio Media Foundation vers PCM |
| windows/Support | Support Swift-WinRT intégré aux projections générées |
| packaging | Métadonnées du bundle Mac et ressources distribuées |
| Tests | Tests du moteur commun et des adaptateurs de chaque plateforme |

CappellaSession réexporte CappellaCore pour ses clients Mac. Swift Package Manager
inclut automatiquement les fichiers Swift de chaque cible ; les fichiers propres
à Windows restent dans la cible Windows.

## Logique métier commune

| Composant | Règles communes |
|---|---|
| ProjectEditing | Création, collage, déplacement et suppression des phrases ; fermeture explicite au playhead ; repères triés/renumérotés ; fusion des rôles |
| ProjectHistory | Annuler/rétablir, groupes de saisie et annulation d'une transaction |
| ProjectFile / AutomaticBackup | Lecture/écriture, normalisation et récupération avec une identité unique par projet ouvert |
| AudioRouting / PCMChannelPreparation | VO/VI par canaux logiques, regroupement des flux, silence de remplissage et inversion par trames d'échantillons |
| PCMPlaybackCache | Lecture PCM WAV/AIFF/AIFC directe, lecture normale par blocs sans cache ; cache réservé au reverse et réutilisé avant décodage |
| ApplicationPreferences | Valeurs enregistrées et validation commune des limites |
| DialogueSearch / ControlNavigation / PlaybackControls | Recherche, navigation et commandes de lecture |

WindowsDocument et ProjectSession restent des adaptateurs de présentation :
callbacks WinUI ou notifications Combine, choix de fichiers, demandes de
confirmation et intégration des fenêtres. AVFoundation et Media Foundation
décodent les médias dans leurs formats natifs ; les règles sur les échantillons
PCM, leurs canaux et leur inversion sont dans le Core. Les codecs disponibles
restent dépendants du système.

Une phrase nouvellement saisie porte pendingEnd jusqu'à sa fermeture explicite
avec Entrée ou un signe de sortie. La borne interne de prévisualisation ne crée
pas de signe de fin visible ou exporté. Les brouillons avec texte sont conservés
dans les fichiers DetX sans inventer de sortie. Le collage à travers une boucle
est autorisé ; le chevauchement d'une autre phrase reste contrôlé.

## Interface Windows

WindowsEditor conserve l'état de présentation et relie les événements.
Ses extensions répartissent les responsabilités :

| Fichier | Responsabilité |
|---|---|
| WindowsLayout | Disposition, séparateurs, barre de titre et thème de la fenêtre |
| WindowsCartouche | Timecode, boucle courante, durée et état VO/VI |
| WindowsScriptView | Liste des répliques et mise à jour de leur sélection |
| WindowsBand | Dessin de la bande, signes et interactions du pointeur |
| WindowsTimelineScroll | Barre horizontale et navigation dans le projet |
| WindowsTimelineMotion | Interpolation du transport et animation du défilement |
| WindowsTimelineText | Saisie native invisible, sélection et curseur dessinés sur la bande |
| WindowsMenus | Menus, coches et raccourcis |
| WindowsDesktopInput | Interception des messages clavier, suivi du redimensionnement et fermeture |
| WindowsDialogs | Infrastructure des dialogues, catégories et actions communes |
| WindowsSearch | Recherche par texte, rôle, casse et mot entier ; navigation suivante |
| WindowsTransportControls | Changement du timestamp et conservation de la position relative au média |
| WindowsFileDialogs | Sélecteurs, ouverture, remplacement et enregistrement |
| WindowsPropertiesPanel | Fichiers associés, rôles importés, métadonnées et repères |
| WindowsPreferencesPanel | Préférences Général, Bande rythmo et Vidéo |
| WindowsRolesPanel | Choix, gestion et portraits des rôles |
| WindowsProjectMedia | Chargement et déchargement des médias au changement de projet |
| WindowsMedia / WindowsAudioPreparation / WindowsReverseAudio | Lecture directe du média, flux PCM à la demande et cache réservé au reverse |
| WindowsDiagnostics | Marqueurs de lancement utilisés par les contrôles CI |

PlaybackControls partage les quatorze vitesses du Shuttle et la vitesse du Jog.
ControlNavigation partage le choix des signes, phrases, rôles, boucles et plans,
ainsi que les bornes accessibles et la sélection de la piste à destination.

DialogueSearch définit les mêmes critères et le même parcours des résultats sur
Mac et Windows, y compris les phrases simultanées et le retour au début.

TimelineScrollRange partage les bornes et la taille de vue entre la barre WinUI
et le NSScroller du Mac (TimelineScroller).

Le champ natif traite Unicode, les accents, AltGr et le presse-papiers ; la bande
dessine le texte étiré. Les événements de sélection ne doivent pas réinjecter un
ancien texte du modèle pendant une frappe. Les références Swift conservées par les
callbacks restent nécessaires même lorsque WinUI conserve le contrôle natif.

## Documents et préférences

Chaque fenêtre principale édite un seul projet. La demande Enregistrer / Ne pas
enregistrer / Annuler précède tout remplacement. Les événements Finder passent
par ExternalFileOpenRouter sur Mac ; Windows traite les arguments de lancement.

Le modèle conserve le XML DetX source pour préserver les informations non exposées
par l'éditeur. En l'absence de cadence déclarée, la lecture utilise 25 i/s.
Les chemins des médias doivent être accessibles sur la machine courante.

Sur Mac, les préférences passent par UserDefaults et AppStorage. Sur Windows,
WindowsSettings écrit les préférences et les proportions des panneaux dans
%APPDATA%/Cappella/preferences.json. Les valeurs de préférence à enregistrer
sont définies une seule fois dans ApplicationPreferences.

AutomaticBackup définit les intervalles et les noms uniques des copies de
récupération. Les adaptateurs choisissent leur dossier et fournissent la position
courante ; une copie de récupération ne remplace jamais le document source.

## Limites connues

La présence d'une fonction dans le code ne certifie pas sa fidélité métier.
Les exports doivent être relus dans le Cappella d'origine sur des copies.

- Compatibilité avec d'autres variantes DetX et avec les anciens fichiers .det à vérifier.
- Lecture inverse : son PCM inversé préparé en arrière-plan, vidéo suivie par recherches d'images. Première préparation et espace temporaire nécessaires ; synchronisation à valider en séance.
- Rendu typographique, codecs et synchronisation à comparer avec les médias réels.
- Protocole Orphée/FTDI, sous-titrage UER et impression d'origine à compléter.
- Les interfaces ne proposent pas encore exactement les mêmes fonctions :
  voir les limites propres à [Windows](WINDOWS.md).
- Les archives ne disposent pas de notarisation Apple ni de signature commerciale Windows.

Les [contrôles automatisés](SCRIPTS.md) vérifient le modèle, la saisie native et
l'ouverture des fenêtres. Ils ne remplacent pas une validation en séance.

La police par défaut de la bande est PreludeFLF (variante italique), embarquée
dans les ressources des distributions Mac et Windows. macOS l'enregistre pour le
processus, WinUI la charge depuis les ressources de l'application. Les anciennes
polices par défaut sont migrées une fois ; les autres choix personnalisés restent
conservés. Les mesures, le texte et le curseur utilisent la même face.

Le collage de phrase propose le rôle et contrôle l'espace sur la piste demandée
avant ce choix, puis à l'insertion. La destination reste celle du lancement de la
commande ; aucun chevauchement n'est écrasé. Les frontières jointives et le passage
à travers une boucle sont autorisés. Une sélection de texte conserve les commandes
natives de copie/coupe ; un presse-papiers de phrase déclenche le collage avec rôle.

Sur Windows, le champ natif invisible reste focusable et ne recouvre pas le texte
dessiné. Le relâchement de la souris restaure uniquement son focus, sans réduire
la sélection à un curseur. Le double-clic utilise le délai et la zone de tolérance
Windows pour sélectionner le mot ; les limites de caractères composés sont
conservées. Le clic simple continue d'ouvrir directement la saisie.

En lecture Windows, le timecode garde l'image courante (arrondi inférieur commun
au Mac) tandis que l'animation conserve la position fractionnaire. Seul le bruit
numérique autour d'une frontière d'image exacte est arrondi à cette frontière.
L'horloge interpole les positions MediaPlayer répétées sans les traiter comme de
nouveaux échantillons ; les petits écarts frais corrigent progressivement la
vitesse, avec un gain fondé sur le temps écoulé et indépendant du rafraîchissement.
La mise en pause reprend la position arrêtée du transport, y compris en reverse.

En lecture Windows, les bornes visuelles des phrases sont indexées lors des
changements du document ou de la présentation. La population de la bande cherche
les intersections par dichotomie dans les débuts triés et les fins maximales
cumulées ; les phrases ouvertes ne sont plus remesurées périodiquement.
Le suivi du script conserve son état entre les entrées et sorties de répliques,
y compris en reverse. Seules les lignes dont la couleur change sont modifiées.
Le timecode et la scrollbar suivent les images du projet ; le mouvement de la
bande reste fractionnaire et animé indépendamment par Windows Composition.

La conversion vers les ticks WinRT arrondit vers le haut pour ne pas retomber
avant une borne à cause de la représentation flottante des secondes.
