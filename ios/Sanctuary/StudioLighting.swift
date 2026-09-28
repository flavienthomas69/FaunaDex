import SceneKit
import UIKit

/// Éclairage studio doux et chaud, esprit diorama :
/// - une lumière principale chaude qui porte des ombres douces ;
/// - une lumière de remplissage froide, sans ombres, pour déboucher le côté sombre ;
/// - une lumière de contour, par l'arrière, pour détacher la silhouette ;
/// - un environnement dégradé (ciel clair / sol ocre) pour l'éclairage physique des matériaux ;
/// - un sol invisible qui ne reçoit que les ombres.
enum StudioLighting {

    static let background = UIColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)   // fond neutre chaud

    static func install(in scene: SCNScene) {
        // Lumière principale : directionnelle, seule l'orientation compte
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1100
        key.color = UIColor(red: 1.0, green: 0.93, blue: 0.84, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 8                       // bords d'ombre adoucis
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.28)
        key.automaticallyAdjustsShadowProjection = true
        key.maximumShadowDistance = 30
        let keyNode = SCNNode()
        keyNode.name = "keyLight"
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)

        // Remplissage : côté opposé, bleuté, sans ombres
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 380
        fill.color = UIColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi * 0.75, 0)
        scene.rootNode.addChildNode(fillNode)

        // Contour : par l'arrière et au-dessus
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 450
        rim.color = UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi, 0)
        scene.rootNode.addChildNode(rimNode)

        // Ambiance générale, faible pour garder le contraste entre facettes
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 180
        ambient.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Environnement : dégradé ciel / sol pour les matériaux physiques
        scene.lightingEnvironment.contents = gradientEnvironment()
        scene.lightingEnvironment.intensity = 0.9

        // Sol qui ne montre que les ombres portées
        let floor = SCNFloor()
        floor.reflectivity = 0
        let shadowCatcher = SCNMaterial()
        shadowCatcher.lightingModel = .shadowOnly
        floor.materials = [shadowCatcher]
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "shadowFloor"
        scene.rootNode.addChildNode(floorNode)
    }

    /// Image équirectangulaire (2:1) : ciel bleu clair en haut, horizon crème, sol ocre en bas.
    private static func gradientEnvironment() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 1).cgColor,
                UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1).cgColor,
                UIColor(red: 0.72, green: 0.60, blue: 0.40, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}
