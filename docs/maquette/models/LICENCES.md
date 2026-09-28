# Modèles 3D de la maquette

Les cervidés, ours, canidés et équidés utilisent les modèles animés ci-dessous. Les autres espèces ne sont pas des fichiers : elles sont sculptées à l'exécution par le moteur de la maquette (champ de distance → maillage lisse articulé).

| Fichier | Auteur | Licence |
|---|---|---|
| stag.json, hind.json, roe.json, bear.json | Quaternius, *Ultimate Animated Animal Pack* ; recoloration, mise à l'échelle et ours tiré du loup par le projet [postojomierz](https://github.com/postojomierz-lang/postojomierz) (`tatry/tools/blender/make_animals.py`) | Modèles d'origine CC0. Le dépôt postojomierz n'indique pas de licence : avant une publication commerciale, refaire l'export depuis le pack Quaternius d'origine (script fourni dans ce dépôt) |
| fox.json | Modèle : PixelMannen ; squelette et animations : tomkranis ; conversion : Khronos glTF-Sample-Models | Modèle CC0, squelette et animations CC-BY 4.0 (créditer tomkranis) |
| horse.json | mirada, projet « ro.me » (exemples officiels three.js) | Distribué avec les exemples three.js ; licence à confirmer avant tout usage commercial |
| stork.json, flamingo.json | mirada, projet « ro.me » (exemples officiels three.js) | Distribués avec les exemples three.js ; licence à confirmer avant tout usage commercial |
| tree-big.json, tree-small.json, palm-short.json, formation-*.json | Kenney (kenney.nl), Nature Kit | CC0 |

Les fichiers Kenney ont été décompressés (Draco → glTF standard) avec `gltf-transform copy`. Tous les modèles sont stockés en glTF JSON auto-contenu (données binaires en base64) pour être servis comme du JSON.
Les couleurs sont recalculées à l'exécution : palette de l'espèce ou couleurs extraites de la photo.
