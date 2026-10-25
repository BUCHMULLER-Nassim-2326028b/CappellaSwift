# Créer une release GitHub

La convention des fichiers est :

    Cappella-VERSION-OS-ARCH-TYPE.extension

OS vaut macOS ou Windows, ARCH vaut x64 ou arm64, et TYPE vaut Portable ou Setup.
Les archives portables contiennent le dossier de l'application ; les Setup Windows
sont des installateurs. macOS est distribué sous forme d'un ZIP contenant Cappella.app.

## Les cinq téléchargements

Pour le tag v1.0.1, la release contient :

- Cappella-1.0.1-macOS-arm64-Portable.zip
- Cappella-1.0.1-Windows-x64-Portable.zip
- Cappella-1.0.1-Windows-x64-Setup.exe
- Cappella-1.0.1-Windows-arm64-Portable.zip
- Cappella-1.0.1-Windows-arm64-Setup.exe

SHA256SUMS.txt contient les empreintes des cinq fichiers.

## Publier

1. Enregistrer les modifications du projet dans Git, puis les pousser.
2. Depuis le dépôt, créer et pousser un nouveau tag :

   ~~~powershell
   git tag v1.0.1
   git push origin v1.0.1
   ~~~

   Choisir un numéro encore inutilisé. Le tag détermine la version des noms de
   fichiers ; ne pas réutiliser ni déplacer un tag déjà publié.

3. Attendre la réussite de **Actions → Prepare GitHub release**. Il compile
   macOS ARM64, Windows x64 et Windows ARM64, puis exécute les vérifications
   existantes. Windows ARM64 utilise un runner Windows ARM64 natif.
4. Ouvrir **Releases**, puis le brouillon créé automatiquement. Vérifier les notes
   et les cinq téléchargements. Pour une bêta, cocher **Set as a pre-release**,
   puis cliquer **Publish release**.

Aucun brouillon n'est créé si une compilation ou une vérification échoue.
Le dépôt n'a pas besoin d'un jeton personnel pour publier ce brouillon :
le workflow utilise le jeton GitHub Actions avec contents: write.

## Télécharger sans publier

Lancer le workflow Mac ou Windows depuis **Actions → Run workflow**.
La matrice Windows produit les deux architectures. Chaque téléchargement est
dans un artefact distinct :

| Artefact Actions | Contenu |
|---|---|
| Cappella-1.0.1-macOS-arm64-Portable.zip | Application macOS ARM64 |
| Cappella-1.0.1-Windows-x64-Portable.zip | Portable Windows x64 |
| Cappella-1.0.1-Windows-x64-Setup.exe | Installateur Windows x64 |
| Cappella-Windows-arm64-Portable | Un ZIP Windows ARM64 |
| Cappella-Windows-arm64-Setup | Un Setup Windows ARM64 |

Les distributions sont envoyées avec upload-artifact v7 et archive: false :
le navigateur télécharge directement le ZIP portable ou le Setup EXE, sans ZIP
supplémentaire. Le nom de l'artefact est celui du fichier, version comprise.
Les récupérations entre jobs utilisent download-artifact v8 et skip-decompress:
true pour conserver les distributions intactes. Les cinq fichiers restent séparés.
Les anciens runs conservent leurs anciennes archives : relancer le workflow pour
obtenir le nouveau format.

## Version unique

La première release publique est 1.0.0. Le développement suivant est 1.0.1.
La seule valeur à modifier pour la prochaine version est `development` dans
Sources/CappellaCore/AppVersion.swift. L'interface et les builds locaux utilisent
cette valeur par défaut. Un tag v-prefixed ou une version explicite au script
peut la remplacer pour une distribution ; la priorité est argument, tag, source.

Le build inscrit la version résolue partout : À propos, vérification des mises à
jour Mac, métadonnées du bundle, propriétés de l'EXE, manifeste Windows, Setup et
noms des cinq fichiers. Les versions numériques Apple/Windows utilisent la partie
X.Y.Z ; l'interface et les noms conservent un éventuel suffixe de préversion.
Info.plist est un modèle rempli lors du packaging, pas une deuxième version à éditer.
Le Setup vérifie que sa version correspond au programme déjà compilé.

En local : -Version pour Windows, premier argument de build-macos.sh pour Mac.

Les portables Windows nécessitent le Windows App Runtime de leur architecture.
Chaque Setup inclut l'installateur Microsoft correspondant. La désinstallation
conserve le runtime partagé et les préférences.

La signature Apple reste ad hoc ; Windows n'a pas de certificat éditeur.
Une release GitHub n'ajoute ni notarisation Apple ni signature Authenticode.
