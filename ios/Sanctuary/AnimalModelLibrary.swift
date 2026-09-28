import SceneKit
import UIKit

/// Fiche d'un modèle 3D importé dans le projet Xcode.
struct AnimalAsset {
    /// Nom du fichier dans le bundle : "owl_lowpoly.usdz", "fox_lowpoly.scn"…
    /// Un fichier .scn peut aussi être rangé dans un dossier .scnassets : "Animals.scnassets/fox.scn".
    let file: String
    /// Hauteur voulue dans la scène (en mètres SceneKit), quelle que soit l'échelle du fichier d'origine.
    let height: Float
    /// Rotation à appliquer si le modèle ne regarde pas vers +Z.
    var yaw: Float = 0
}

/// Espèce → modèle. On cherche d'abord l'espèce exacte, puis sa famille, pour qu'un seul modèle serve
/// à plusieurs espèces proches (recolorées d'après la photo).
enum AnimalAssetCatalog {
    static let bySpecies: [String: AnimalAsset] = [
        "Strix aluco": AnimalAsset(file: "owl_lowpoly.usdz", height: 0.6),
        "Vulpes vulpes": AnimalAsset(file: "fox_lowpoly.usdz", height: 0.55),
        "Chamaeleo calyptratus": AnimalAsset(file: "chameleon_lowpoly.usdz", height: 0.3),
        "Cervus elaphus": AnimalAsset(file: "stag.usdz", height: 1.4),
        "Capreolus capreolus": AnimalAsset(file: "roe.usdz", height: 0.75),
    ]
    static let byFamily: [String: AnimalAsset] = [
        "Strigidae": AnimalAsset(file: "owl_lowpoly.usdz", height: 0.55),
        "Canidae": AnimalAsset(file: "fox_lowpoly.usdz", height: 0.6),
        "Chamaeleonidae": AnimalAsset(file: "chameleon_lowpoly.usdz", height: 0.3),
        // Modèles animés déjà testés dans la maquette (docs/maquette/models, à convertir en .usdz avec Reality Converter)
        "Cervidae": AnimalAsset(file: "hind.usdz", height: 1.1),
        "Ursidae": AnimalAsset(file: "bear.usdz", height: 1.0),
        "Equidae": AnimalAsset(file: "horse.usdz", height: 1.5),
    ]

    static func asset(scientificName: String, family: String?) -> AnimalAsset? {
        bySpecies[scientificName] ?? family.flatMap { byFamily[$0] }
    }
}

/// Charge chaque fichier une seule fois, lui applique le style papier plié, puis fournit des copies légères
/// (`clone()` partage géométries et matériaux : dix renards ne coûtent pas plus de mémoire qu'un seul).
final class AnimalModelLibrary {
    static let shared = AnimalModelLibrary()
    private var prototypes: [String: SCNNode] = [:]

    /// Exemplaire prêt à placer : mis à l'échelle, pieds posés à y = 0, animations en boucle.
    func instance(of asset: AnimalAsset) -> SCNNode? {
        guard let prototype = prototype(for: asset.file) else { return nil }
        let model = prototype.clone()

        // Mise à l'échelle d'après la boîte englobante (le nœud racine englobe toute sa hiérarchie)
        let (minB, maxB) = model.boundingBox
        let sourceHeight = max(maxB.y - minB.y, 0.0001)
        let k = asset.height / sourceHeight
        model.scale = SCNVector3(k, k, k)
        model.position = SCNVector3(-(minB.x + maxB.x) / 2 * k, -minB.y * k, -(minB.z + maxB.z) / 2 * k)

        // Conteneur : on déplace et oriente le conteneur, le modèle reste centré dedans
        let container = SCNNode()
        container.eulerAngles.y = asset.yaw
        container.addChildNode(model)
        Self.playAllAnimations(in: model)
        return container
    }

    private func prototype(for file: String) -> SCNNode? {
        if let cached = prototypes[file] { return cached }
        guard let loaded = Self.load(file) else { return nil }
        PapercraftStyle.apply(to: loaded)
        prototypes[file] = loaded
        return loaded
    }

    /// Charge un .usdz ou un .scn du bundle Xcode.
    /// SceneKit ne lit pas le glTF (.glb) : le convertir avant en .usdz (Reality Converter, Blender).
    static func load(_ file: String) -> SCNNode? {
        let scene: SCNScene?
        if let named = SCNScene(named: file) {
            scene = named
        } else {
            let base = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
            scene = Bundle.main.url(forResource: base, withExtension: ext).flatMap { try? SCNScene(url: $0, options: nil) }
        }
        guard let scene else {
            print("FaunaDex 3D : fichier \(file) introuvable dans le bundle (vérifier « Target Membership »).")
            return nil
        }
        let wrapper = SCNNode()
        wrapper.name = file
        for child in scene.rootNode.childNodes { wrapper.addChildNode(child) }
        return wrapper
    }

    /// Joue en boucle une seule animation par nœud : celle dont le nom contient `preferred` (« idle » par défaut),
    /// sinon la première. Les autres (marche, galop…) sont mises en pause : les jouer toutes à la fois mélangerait les poses.
    /// Attention : un .usdz ne garde souvent qu'une seule animation ; exporter un fichier par clip si besoin.
    static func playAllAnimations(in root: SCNNode, preferred: String = "idle") {
        root.enumerateHierarchy { node, _ in
            let keys = node.animationKeys
            guard !keys.isEmpty else { return }
            let chosen = keys.first { $0.lowercased().contains(preferred) } ?? keys[0]
            for key in keys {
                guard let player = node.animationPlayer(forKey: key) else { continue }
                if key == chosen {
                    player.animation.repeatCount = .greatestFiniteMagnitude
                    player.play()
                } else {
                    player.stop()
                }
            }
        }
    }
}
