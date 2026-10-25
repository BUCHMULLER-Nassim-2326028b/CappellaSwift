# Cappella Windows

L'application utilise WinUI 3 depuis Swift avec Swift-WinRT. Le moteur CappellaCore
est partagé avec le Mac ; SwiftUI et AppKit restent propres à macOS.

## Installer Cappella

Deux distributions sont conservées sur GitHub Releases :

- **Setup** : Cappella-VERSION-Windows-ARCH-Setup.exe, assistant en français.
  Il installe dans %LOCALAPPDATA%/Programs/Cappella, crée le raccourci du menu
  Démarrer et propose celui du Bureau. Il ajoute Cappella aux applications
  disponibles pour ouvrir les .detx et .cappellaproject, sans remplacer le choix
  par défaut de Windows. La désinstallation se fait depuis les paramètres Windows.
- **ZIP portable** : Cappella-VERSION-Windows-ARCH-Portable.zip, à extraire ; il nécessite le runtime
  installé séparément.

Le Setup contient l'installateur Microsoft signé du Windows App Runtime 1.7 de la même architecture (x64 ou ARM64).
Il vérifie la version nécessaire pour l'utilisateur courant et installe le runtime
uniquement si elle manque. Le runtime et le script de préparation sont extraits
temporairement, jamais copiés dans le dossier de Cappella. Une erreur de préparation
interrompt l'installation et affiche un message. La désinstallation conserve les
préférences et le runtime partagé avec d'autres applications.

## Lancer l'archive

Windows x64 ou ARM64 avec Windows App Runtime 1.7 correspondant. Extraire tout le ZIP et conserver les DLL,
Resources et Licenses auprès de Cappella.exe. Les DLL Swift sont incluses dans
l'archive ; Windows App Runtime 1.7 de la même architecture (x64 ou ARM64) doit être installé séparément
([téléchargements Microsoft](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads-archive)).
Le script windows/Installer-runtime.ps1 reste dans le dépôt pour le développement
et la CI. Ce script et la documentation ne sont pas ajoutés au ZIP distribué.

## Compiler

Installer Swift pour Windows, Visual Studio 2022 avec les outils C++ et un Windows
SDK. La CI utilise Swift 6.2 ; le développement local utilise aussi Swift 6.4.1.

    .\scripts\build-windows.ps1

Puis, pour réutiliser les projections déjà générées :

    .\scripts\build-windows.ps1 -SkipPrepare

Ajouter -Configuration debug pour un binaire de développement. La configuration
par défaut est release. Résultats : dist/Cappella-Windows-ARCH/Cappella.exe et
dist/Cappella-VERSION-Windows-ARCH-Portable.zip.

La préparation peut également être lancée séparément :

    .\scripts\prepare-windows.ps1

Les archives NuGet sont épinglées et vérifiées par SHA-256. Les caches .windows
et .build restent locaux. Une configuration de projections modifiée déclenche
leur régénération même avec -SkipPrepare. Le support manuel WinUI/WinAppSDK est
resynchronisé avant compilation sans régénérer les projections.

Les [scripts et contrôles CI](SCRIPTS.md) et le [guide de release](RELEASES.md)
décrivent les autres commandes.

## Documents et réglages

Ouvrir remplace le projet courant dans la même fenêtre après confirmation des
modifications non enregistrées. Chaque lancement de l'exécutable peut créer une
instance indépendante. Fermer la fenêtre principale ferme sa projection et termine
cette instance.

Les propriétés regroupent Fichier, Programme, Production, Description et Repères.
La catégorie Fichier relie la vidéo, le son externe et la liste de rôles à importer.
Les changements sont validés par OK ou Appliquer.

Les préférences Général, Bande rythmo et Vidéo sont stockées dans
%APPDATA%/Cappella/preferences.json, avec les proportions des panneaux.
La sauvegarde automatique est désactivable et son intervalle est réglable.
Ses copies de récupération sont stockées dans le dossier de données utilisateur
Cappella/Autosaves, séparément du fichier original.

## Édition des phrases

Une nouvelle phrase reste ouverte pendant la saisie et la lecture. Haut et Bas
interceptent le champ de texte pour lancer la lecture normale ou inverse.
Entrée ferme ensuite la phrase exactement au playhead. La fin de prévisualisation
interne n'apparaît pas comme un signe de sortie.

Le clic droit sur une piste vide propose Coller. Le point cliqué devient la
destination au choix de cette action, puis le rôle est confirmé avant insertion.
Le collage à travers une boucle est autorisé. L'historique et les règles
d'édition sont partagés avec Mac.

## Contrôle de la lecture

Mac et Windows partagent les vitesses du Shuttle, de x0.125 à x10 dans chaque
direction (x0.125, x0.25, x0.5, x0.75, x1, x3, x10). La vitesse active est cochée ;
sélectionner une vitesse la fixe, même si elle était déjà active. Jog avant et
Jog arrière lancent une lecture continue à x0.25 dans le sens choisi. Stop ou
Espace l'arrête. Les touches Haut/Bas et V/B/N/virgule restent des bascules.

Les menus proposent les mêmes navigations : signes, phrases, phrases du rôle,
boucles et plans. Les cibles hors du média sont ignorées sur les deux plateformes.
Changer le timestamp décale l'origine, les dialogues, leurs signes et les
repères tout en conservant la position relative au média. Machine Orphée reste
désactivée sur les deux plateformes : son protocole matériel n'est pas porté.

## Audio et limites

Le son séparé remplace celui de la vidéo. Les décodeurs natifs fournissent des
flux PCM au Core, qui conserve l'ordre des canaux : deux canaux donnent VO/VI
mono ; quatre canaux donnent VO/VI stéréo, y compris quatre flux mono. Les flux
regroupés doivent avoir la même cadence et le même format PCM. Les fichiers
AIFF/AIFC PCM sont convertis par le Core ; les autres codecs dépendent de Media
Foundation.

La lecture normale ouvre directement le média, sans attendre le cache inversé.
Pour les WAV/AIFF/AIFC PCM, WindowsPCMSource fournit à WinRT de petits blocs lus
à la demande dans le fichier d'origine ; le Core sélectionne les canaux VO/VI et
adapte l'ordre des octets sans créer de fichier de lecture avant. Les PCM entiers
conservent leur profondeur d'origine ; les PCM flottants sont fournis en PCM
32 bits. Les autres formats sont confiés directement au lecteur natif.

Le cache est réservé au reverse et commence à la première demande de marche
arrière. Sa préparation s'exécute en arrière-plan et ne remplace, ne recharge,
ni ne met en pause les lecteurs de marche avant à son achèvement. Un cache terminé
est réutilisé avant tout décodage lors d'une demande ultérieure. L'image recule
pendant cette première préparation et le son rejoint la position courante dès
qu'il est prêt. Changer de vitesse dans le même sens ne repositionne pas les
lecteurs. Le son externe conserve la priorité et le choix VO/VI reste actif.
La préparation travaille par blocs, respecte l'annulation et supprime
ses fichiers de décodage temporaires au déchargement. Le cache inversé terminé reste
dans le répertoire temporaire système pour éviter une nouvelle préparation. Elle nécessite de l'espace disque ;
chaque piste WAV de sortie est limitée à 4 Go. Les codecs et la synchronisation
doivent encore être validés sur des médias réels.

L'enregistrement microphone et la détection automatique des plans restent propres
au Mac. La projection Windows affiche la vidéo ; elle ne reproduit pas encore
l'ensemble de l'écran de contrôle Mac. Certains outils avancés restent moins
complets sur Windows.

La recherche (Ctrl+F) partage son moteur avec le Mac : texte littéral, filtre
par rôle, respect de la casse et mot entier Unicode. Suivant conserve le dialogue
ouvert et parcourt les phrases par timecode et piste, puis revient au début.
F3 reprend la recherche avec les derniers critères ; Annuler ferme le dialogue.

Les dialogues Propriétés et Préférences gardent leur NavigationView latérale,
avec des pages défilantes, des libellés au-dessus des champs et des groupes
distincts. Les champs courts sont disposés par deux quand cela facilite la
lecture. Les fenêtres de rôles séparent la liste du portrait et de la fiche ;
les formulaires courts sélectionnent leur premier champ à l'ouverture.
Les messages longs reviennent à la ligne et les erreurs de validation restent
visibles sous le formulaire.

Les dialogues internes suivent le thème de l'application ; les sélecteurs de
fichiers Windows conservent le thème système. La validation des codecs, de la
fluidité et des commutations VO/VI nécessite des médias réels.

## Construire le Setup

Installer [Inno Setup 6](https://jrsoftware.org/isinfo.php), puis, après la compilation :

    .\scripts\build-windows-installer.ps1 -Version 1.0.1

Cette commande réutilise dist/Cappella-Windows-ARCH sans recompiler Swift. Elle
télécharge le runtime Microsoft dans .windows/installer lors de la première
utilisation, vérifie sa signature Authenticode et l'intègre au Setup.
Le ZIP portable n'est pas modifié.

La CI Windows construit les deux distributions. Pour une release, le numéro du
Setup vient du tag vVERSION ; hors tag, il vient de packaging/Info.plist si
-Version n'est pas précisé. Le compilateur Inno Setup est déjà présent sur
l'image GitHub windows-2022. En local, -Compiler permet d'indiquer ISCC.exe.

Le Setup n'est pas signé avec un certificat éditeur ; sa génération ne supprime
pas les éventuels avertissements SmartScreen. Les contrôles CI actuels lancent
l'application ; ils ne valident pas encore un cycle installation/désinstallation.

## Taille des distributions

Les builds release éliminent le code non référencé et fusionnent les fonctions
identiques à l'édition des liens (OPT:REF et OPT:ICF). Le packaging retire ensuite
les sections de débogage de la copie distribuée, avant l'ajout de l'icône.
L'exécutable original et ses informations de débogage restent dans .build.
Les métadonnées Swift de réflexion, les tables de déroulement de pile et les
ressources de l'application sont conservées.

Les DLL sont sélectionnées à partir des imports normaux et différés, en parcourant
leurs dépendances transitives. Les modules Foundation, ICU, les composants de
diagnostic Swift et les bibliothèques VC++ sont conservés pour les chargements
dynamiques. Les DLL éditeur ne sont pas modifiées. Les builds debug conservent
toutes les DLL et leurs informations de débogage.

Le ZIP et le Setup réutilisent le même dossier allégé. Le Setup contient en plus
l'installateur Microsoft du Windows App Runtime ; ce poids ne fait pas partie de
l'application installée. Le script affiche la taille finale décompressée.

La configuration windows/projections.json limite les contrôles WinUI explicitement
demandés aux API utilisées. Swift-WinRT génère aussi leurs types dépendants.
Les images sont limitées à BitmapImage plutôt qu'à tout le namespace Imaging ;
les animations de la rythmo utilisent toujours Windows Composition.
Une modification de cette configuration invalide automatiquement -SkipPrepare.
La préparation retire les anciens fichiers Swift générés avant de régénérer,
pour éviter de recompiler des namespaces qui ne sont plus nécessaires. Les fichiers
de support manuels sont conservés.

Ce filtrage réduit le code source généré ; son effet exact sur l'exécutable doit
être mesuré après une nouvelle compilation release. Les optimisations de taille
qui pourraient ralentir le moteur (-Osize) ne sont pas activées.

## Architecture

La CI compile nativement sur windows-2022 pour x64 et windows-11-arm pour ARM64.
Elle produit un portable et un Setup par architecture, chacun dans son artefact.
Les fichiers suivent la convention décrite dans [RELEASES.md](RELEASES.md).

Sur une machine équipée de Swift, des outils C++ et des runtimes de la cible :

    .\scripts\build-windows.ps1 -SkipPrepare -Architecture arm64 -Version 1.0.1
    .\scripts\build-windows-installer.ps1 -Architecture arm64 -Version 1.0.1

Remplacer arm64 par x64 pour Intel/AMD. Le script vérifie l'architecture PE du
binaire et sélectionne les DLL Swift correspondantes. Le Setup ARM64 embarque
le runtime Microsoft ARM64 et refuse une installation sur un système x64.
Pour une première build ARM64, utiliser de préférence le workflow natif GitHub ;
un environnement Swift x64 seul ne garantit pas la présence du runtime ARM64.
