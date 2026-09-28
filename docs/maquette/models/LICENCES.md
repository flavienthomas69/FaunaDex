# Modèles 3D de la maquette

Les mammifères et la plupart des oiseaux ne sont pas des fichiers : ils sont sculptés à l'exécution par le moteur de la maquette (champ de distance → maillage lisse articulé).

| Fichier | Auteur | Licence |
|---|---|---|
| stork.json, flamingo.json | mirada, projet « ro.me » (exemples officiels three.js) | Distribués avec les exemples three.js ; licence à confirmer avant tout usage commercial |
| tree-big.json, tree-small.json, palm-short.json, formation-*.json | Kenney (kenney.nl), Nature Kit | CC0 |

Les fichiers Kenney ont été décompressés (Draco → glTF standard) avec `gltf-transform copy`. Tous les modèles sont stockés en glTF JSON auto-contenu (données binaires en base64) pour être servis comme du JSON.
Les couleurs sont recalculées à l'exécution : palette de l'espèce ou couleurs extraites de la photo.
