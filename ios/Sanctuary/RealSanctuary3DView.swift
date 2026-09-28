import SwiftUI
import SceneKit

/// Animal à afficher dans le Sanctuaire.
struct SanctuaryAnimal: Identifiable, Equatable {
    let id: String                 // identifiant de la capture
    let scientificName: String     // "Strix aluco"
    let family: String?            // "Strigidae"
    var position: SIMD2<Float>     // position au sol (x, z)
    var tint: UIColor? = nil       // couleur dominante de la photo, si on veut personnaliser
}

/// Sanctuaire 3D en SceneKit : charge les modèles importés (.usdz / .scn), style papier plié, éclairage studio.
/// Les animaux ajoutés après l'ouverture apparaissent avec un rebond.
struct RealSanctuary3DView: UIViewRepresentable {
    var animals: [SanctuaryAnimal]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.backgroundColor = StudioLighting.background

        // 1. Éclairage studio
        StudioLighting.install(in: scene)

        // 2. Caméra : focale longue et légère plongée, pour l'effet diorama miniature
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.05
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Assez près pour que des animaux de 0,3 à 0,6 m remplissent l'écran d'un téléphone en portrait
        cameraNode.position = SCNVector3(0, 1.1, 3.0)
        cameraNode.look(at: SCNVector3(0, 0.28, 0))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // 3. Animaux
        context.coordinator.sync(animals, in: scene, animated: false)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene else { return }
        context.coordinator.sync(animals, in: scene, animated: true)
    }

    final class Coordinator {
        private var nodes: [String: SCNNode] = [:]

        /// Ajoute les nouveaux animaux, retire ceux qui ne sont plus là, met à jour les positions.
        func sync(_ animals: [SanctuaryAnimal], in scene: SCNScene, animated: Bool) {
            let wanted = Set(animals.map(\.id))
            for (id, node) in nodes where !wanted.contains(id) {
                node.removeFromParentNode()
                nodes[id] = nil
            }
            for animal in animals {
                if let node = nodes[animal.id] {
                    node.position = SCNVector3(animal.position.x, 0, animal.position.y)
                    continue
                }
                guard let asset = AnimalAssetCatalog.asset(scientificName: animal.scientificName, family: animal.family),
                      let node = AnimalModelLibrary.shared.instance(of: asset) else {
                    print("FaunaDex 3D : pas de modèle pour \(animal.scientificName).")
                    continue
                }
                if let tint = animal.tint { PapercraftStyle.tint(node, with: tint) }
                node.position = SCNVector3(animal.position.x, 0, animal.position.y)
                scene.rootNode.addChildNode(node)
                nodes[animal.id] = node
                if animated { Self.playSpawn(on: node) } else { Self.startIdle(on: node) }
            }
        }

        /// Apparition : l'animal jaillit du sol avec un rebond, puis respire.
        static func playSpawn(on node: SCNNode) {
            node.scale = SCNVector3(0.01, 0.01, 0.01)
            let pop = SCNAction.customAction(duration: 0.8) { n, elapsed in
                let t = Float(elapsed / 0.8) - 1
                let s = max(0.01, 1 + 2.70158 * t * t * t + 1.70158 * t * t)   // easeOutBack
                n.scale = SCNVector3(s, s, s)
            }
            node.runAction(pop) { startIdle(on: node) }
        }

        /// Respiration légère, utile surtout pour les modèles sans animation.
        static func startIdle(on node: SCNNode) {
            let inhale = SCNAction.scale(to: 1.025, duration: 1.4)
            inhale.timingMode = .easeInEaseOut
            let exhale = SCNAction.scale(to: 1.0, duration: 1.4)
            exhale.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([inhale, exhale])), forKey: "idle")
        }
    }
}

#Preview {
    RealSanctuary3DView(animals: [
        SanctuaryAnimal(id: "1", scientificName: "Strix aluco", family: "Strigidae", position: [-0.42, -0.05]),
        SanctuaryAnimal(id: "2", scientificName: "Vulpes vulpes", family: "Canidae", position: [0.42, 0.1]),
    ])
    .ignoresSafeArea()
}
