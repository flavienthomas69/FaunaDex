import SceneKit
import UIKit

/// Style « papier plié » appliqué aux modèles importés (.usdz / .scn) :
/// matière mate et une normale par facette, pour garder des facettes nettes.
///
/// `SCNMaterial` n'a pas de propriété `isFlatShaded` : dans SceneKit, l'aspect facetté dépend des normales.
/// Un petit shader recalcule donc la normale de chaque facette à partir de la géométrie affichée.
/// Cela fonctionne aussi sur les modèles animés (squelette ou morphing), car le calcul est refait à chaque image.
enum PapercraftStyle {

    /// Normale de la facette = produit vectoriel des dérivées écran de la position (espace vue).
    /// Le signe est corrigé pour que la normale regarde toujours la caméra, quel que soit le sens des triangles.
    static let flatNormalModifier = """
    #pragma body
    float3 faceNormal = normalize(cross(dfdx(_surface.position), dfdy(_surface.position)));
    if (dot(faceNormal, _surface.view) < 0.0) {
        faceNormal = -faceNormal;
    }
    _surface.normal = faceNormal;
    """

    /// Applique le style à toute la hiérarchie d'un modèle.
    /// - Parameters:
    ///   - root: nœud racine du modèle chargé.
    ///   - flatShading: `true` pour forcer les facettes (recommandé pour le style papercraft).
    ///   - roughness: 0,85 à 0,95 donne l'aspect papier mat.
    static func apply(to root: SCNNode, flatShading: Bool = true, roughness: CGFloat = 0.9) {
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            node.castsShadow = true
            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                material.roughness.contents = roughness
                material.metalness.contents = 0.0
                // Les cartes de normales et de relief des modèles générés par IA contredisent l'aspect papier
                material.normal.contents = nil
                material.isDoubleSided = false
                if flatShading {
                    var modifiers = material.shaderModifiers ?? [:]
                    modifiers[.surface] = flatNormalModifier
                    material.shaderModifiers = modifiers
                }
            }
        }
    }

    /// Teinte un exemplaire avec une couleur (par exemple la couleur dominante de la photo de l'utilisateur).
    /// La géométrie et les matériaux sont copiés : les autres exemplaires du même modèle ne changent pas.
    /// Les maillages à squelette (`skinner`) sont laissés tels quels : remplacer leur géométrie casserait le lien
    /// avec les os. Pour eux, préférer une texture-palette par espèce (voir docs/REFONTE_3D.md, § 2.3).
    static func tint(_ root: SCNNode, with color: UIColor) {
        root.enumerateHierarchy { node, _ in
            guard node.skinner == nil, let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            geometry.materials = geometry.materials.map { original in
                let material = original.copy() as! SCNMaterial
                material.multiply.contents = color
                return material
            }
            node.geometry = geometry
        }
    }
}
