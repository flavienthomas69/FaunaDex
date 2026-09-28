# Sanctuaire 3D iOS (SceneKit)

Ce dossier contient le Sanctuaire en SceneKit. Il charge des modèles 3D importés (`.usdz` ou `.scn`) au lieu de générer les animaux en code, et leur applique un style papier plié avec un éclairage studio.

| Fichier | Rôle |
|---|---|
| `Sanctuary/RealSanctuary3DView.swift` | Vue SwiftUI (`UIViewRepresentable`) : scène, caméra diorama, ajout et retrait des animaux, animation d'apparition |
| `Sanctuary/AnimalModelLibrary.swift` | Catalogue espèce/famille → fichier, chargement unique puis copies légères, mise à l'échelle, animations en boucle |
| `Sanctuary/PapercraftStyle.swift` | Matière mate et facettes nettes (normale par face calculée dans un shader), teinte d'après la photo |
| `Sanctuary/StudioLighting.swift` | Lumière principale chaude à ombres douces, remplissage, contour, environnement dégradé, sol qui ne montre que les ombres |

## Intégration dans Xcode

1. Glisser le dossier `Sanctuary/` dans le projet et cocher la cible de l'app.
2. Ajouter les modèles au projet : `owl_lowpoly.usdz`, `fox_lowpoly.usdz`, etc. Vérifier **Target Membership** dans l'inspecteur de fichier. Les `.scn` peuvent aller dans un dossier `Animals.scnassets`.
3. Relier les espèces aux fichiers dans `AnimalAssetCatalog` : l'espèce exacte, sinon la famille.
4. Afficher la vue :
   ```swift
   RealSanctuary3DView(animals: captures.map {
       SanctuaryAnimal(id: $0.id, scientificName: $0.sci, family: $0.family, position: $0.spot)
   })
   ```

**Formats acceptés**
- SceneKit lit `.usdz`, `.scn`, `.dae` et `.obj`, mais pas le glTF (`.glb` / `.gltf`).
- Convertir d'abord en `.usdz`, avec **Reality Converter** (Apple, gratuit) ou l'export USD de Blender.
- Les modèles produits par Meshy ou Tripo3D s'exportent directement en `.usdz` ou `.glb`.

## Notes techniques

- **`isFlatShaded` n'existe pas dans SceneKit.** L'aspect facetté vient des normales. `PapercraftStyle` ajoute un modificateur de shader : la normale de chaque pixel est celle de sa facette, calculée à partir des dérivées de la position. Cela marche aussi sur les modèles animés (squelette, morphing), sans modifier les fichiers.
- **Mémoire :** chaque fichier est chargé une seule fois. Les exemplaires utilisent `clone()`, qui partage géométrie et matériaux.
- **Animations :** celles du fichier (marche, repos…) sont jouées en boucle. Les modèles sans animation « respirent » légèrement.
- **Couleurs de la photo :** `PapercraftStyle.tint` multiplie la couleur des matériaux, sauf sur les maillages à squelette. Pour ceux-là, utiliser une texture-palette par espèce (voir `docs/REFONTE_3D.md`, § 2.3).
- **Limites :**
  - le code n'a pas pu être compilé dans cet environnement (pas de compilateur Swift) ; le compiler dans Xcode et me renvoyer les erreurs éventuelles ;
  - SceneKit n'évolue plus. Pour la suite, le même découpage (catalogue, style, lumière, vue) se transpose en RealityKit (`RealityView`, `Entity(named:)`).
