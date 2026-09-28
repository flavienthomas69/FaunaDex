# Refonte graphique 3D « Low Poly moderne » — plan d'exécution

Objectif : passer le Sanctuaire et l'interface à une direction artistique **low poly moderne** : facettes nettes, couleurs vives, lumière douce et chaude, esprit diorama. Les références sont Monument Valley, Animal Crossing et les trois images de référence (hibou, caméléon, renard en papier plié).

On ne repart pas de zéro : la logique de l'app reste (capture, identification, collection, badges, quêtes). On remplace la couche de rendu, par étapes.

> **Où en est ce dépôt.** Le dépôt `FaunaDex` ne contient pas de code Swift, SceneKit ou RealityKit. On y trouve la conception (`docs/CONCEPTION.md`), les services back-end (`services/`) et la maquette web three.js (`docs/maquette/`). Ce plan vise l'app iOS native décrite dans la demande.
>
> **Étape 1 déjà prototypée.** La maquette web applique l'étape 1 et une partie de l'étape 7 :
> - animaux à facettes façon papier plié ;
> - lumière chaude ;
> - animation d'apparition.
>
> Elle sert de référence visuelle testable pour les artistes et les développeurs iOS.

---

## Ordre d'exécution (du plus critique au moins critique)

| # | Étape | Pourquoi à ce rang | Durée indicative |
|---|---|---|---|
| 1 | Charte low poly (couleurs, lumière, matière, budgets) | Tout le reste en dépend ; sans charte, chaque asset part dans une direction différente | 2–3 j |
| 2 | Pipeline des animaux (sources, retouche, rig, recoloration, export USDZ) | Les animaux sont le cœur émotionnel du jeu et le poste le plus coûteux ; c'est ce qui paraît « brouillon » aujourd'hui | 2 sem. pour le pipeline + 20 espèces pilotes |
| 3 | Isoler le moteur 3D dans le code Swift | Permet de brancher les nouveaux assets sans casser l'app, et de faire les étapes 4 à 8 en parallèle | 3–5 j |
| 4 | Diorama du Sanctuaire (îles modulaires par biome) | Le décor donne l'effet « waouh » d'ensemble | 1–2 sem. |
| 5 | Lumière, ciel, cycle jour/nuit et météo réels | Donne vie au diorama ; dépend de 3 et 4 | 1 sem. |
| 6 | Particules (feuilles, lucioles, pluie, pollen) | Finition d'ambiance | 3–4 j |
| 7 | Interface 2D harmonisée, transitions, apparition « waouh » | Cohérence globale et plaisir de capture | 1–2 sem. |
| 8 | Optimisation (LOD, mémoire, 60 FPS) | À mesurer dès l'étape 2, à consolider à la fin | continu + 1 sem. |

---

## Étape 1 — Charte esthétique low poly

**Palette.** Couleurs vives mais légèrement désaturées, jamais de noir pur ni de blanc pur.

| Rôle | Couleurs (sRGB) |
|---|---|
| Forêt | `#2F6B3A` `#4E8A3A` `#7BB356` |
| Prairie | `#9BCB5E` `#C8E08A` |
| Savane | `#E0C27A` `#C99A4E` `#8E6B3A` |
| Jungle | `#1F7A5C` `#3FA66B` `#9ED36A` |
| Océan / eau | `#2E8BC0` `#5BB8D9` `#A9E2EE` |
| Roche | `#8E8A80` `#B7B2A6` |
| Ciel jour → coucher | `#BFE3FF` → `#FFD3A5` → `#F49A7A` |
| Accents UI | `#F2C14E` (or), `#E86A4A` (corail), `#4FA3A5` (sarcelle) |

**Matière.**
- Aplats de couleur par facette, sans textures photo ni cartes de normales.
- Rugosité mate (0,8 à 0,9) et métal à 0.
- Une légère variation de teinte d'une facette à l'autre (±4 %) donne l'aspect papier plié des références.

**Géométrie.**
- Facettes lisibles : 8 à 12 faces sur le tour d'une patte, 10 à 16 sur le tour du corps.
- Ombrage à plat (normales par face).
- Silhouettes exagérées à la manière d'un jouet : tête un peu grosse, pattes fines.

**Budgets par asset :**
- animal : 1 500 à 4 000 triangles, 1 matériau, 1 texture-palette de 64×64 ;
- élément de décor : 50 à 800 triangles ;
- île-biome complète : 15 000 triangles au maximum.

**Lumière.**
- Soleil chaud (`#FFE6C4`) avec des ombres douces.
- Lumière d'ambiance ciel/sol (ciel bleu clair, sol ocre) pour déboucher les ombres.
- Tone mapping filmique et légère brume de profondeur couleur ciel.

**Livrable.** Une planche de style d'une page, avec la palette, 3 animaux de référence et 1 île, validée avant la production en série.

---

## Étape 2 — Pipeline des animaux (le plus critique)

### 2.1 D'où viennent les modèles

| Source | Style | Licence | Usage conseillé |
|---|---|---|---|
| **Quaternius** (quaternius.com) | Low poly propre, animé (marche, course, repos) | CC0 | Base pour ~50 espèces courantes |
| **Kenney** (kenney.nl) | Décor low poly | CC0 | Arbres, rochers, plantes |
| **Poly Pizza** (poly.pizza) | Très varié | CC0 / CC-BY selon l'auteur | Compléments ; vérifier chaque licence |
| **Sketchfab** (filtre « Downloadable » + licence CC0/CC-BY) | Très varié | CC-BY : créditer l'auteur | Espèces rares ; qualité à trier |
| **Synty POLYGON** (payant) | Low poly très homogène | Licence commerciale | Si budget : cohérence immédiate |
| **Meshy / Tripo3D** (génération IA texte ou image → 3D) | Réglable (« low poly », « papercraft ») | Selon l'abonnement : vérifier les droits commerciaux, souvent réservés aux offres payantes | Accélérer les ~1 000 espèces du catalogue ; retouche obligatoire |
| **Commande à un artiste 3D** | Sur mesure | Cession de droits | 20 à 30 espèces « vitrines » (renard, hibou, cerf…) |

**Stratégie recommandée.** Il ne faut pas modéliser les 60 000 espèces. On prévoit :
- **~40 gabarits par famille** (canidé, félin, cervidé, bovidé, passereau, rapace, anatidé, échassier, lézard, caméléon, grenouille, papillon, coléoptère, poisson…) ;
- **des variantes par couleur** : recoloration selon la palette de l'espèce, ou de la photo de l'utilisateur ;
- **des modèles dédiés** pour les espèces vedettes.

La maquette fonctionne déjà ainsi (gabarits par ordre et famille).

### 2.2 Fabrication d'un modèle (Blender, gratuit)

1. **Importer** la source (Quaternius, Meshy…) dans Blender.
2. **Simplifier.** Appliquer le modificateur *Decimate* (mode *Collapse*) jusqu'au budget, puis *Shade Flat*. Pour un rendu papier plié, décimer fort et retoucher à la main les arêtes du museau et des oreilles.
3. **Peindre avec une palette.** Mettre les UV de chaque zone dans une case d'une texture-palette de 64×64 : 8×8 cases pour le dos, le ventre, les pattes, le museau, les yeux, le bec, etc. C'est la méthode standard du low poly : un seul matériau, une seule petite texture.
4. **Rigger.** Utiliser un squelette standard par gabarit, avec les mêmes noms d'os pour toute la famille (`spine_01`, `neck`, `head`, `leg_fl_upper`…). Les animations se partagent ainsi entre espèces.
5. **Animer.** Prévoir des clips courts et bouclés : `idle`, `walk`, `run`, `eat`, `sleep`, `fly`, `swim`, `happy` (réaction au toucher).
6. **Exporter** en glTF 2.0 (`.glb`), la source unique versionnée.
7. **Convertir en USDZ** pour iOS :
   - Reality Converter (Apple) ;
   - ou en ligne de commande avec `usdzconvert` / `xcrun usdz_converter` selon la version de Xcode ;
   - ou avec l'export USD de Blender. Dans ce cas, vérifier que les animations squelettiques passent.
8. **Contrôler automatiquement** (script CI) : nombre de triangles, présence des 8 clips, noms d'os conformes, taille < 400 Ko.

### 2.3 Recoloration d'après la photo (spécificité FaunaDex)

L'app extrait déjà une palette de la photo (couleur dominante, claire, sombre). Avec la texture-palette, recolorer revient à **remplacer les cases de la texture** au chargement. On ne touche ni au modèle ni aux UV : la recoloration est instantanée et le coût mémoire quasi nul.

- Chaque case porte un **rôle** (dos, ventre, pattes…) décrit dans un petit fichier JSON joint au modèle.
- Le rôle est rempli par la couleur de la photo correspondante, avec des bornes de saturation pour garder la charte.

### 2.4 Catalogue d'assets

```
Assets3D/
  catalog.json              # espèce → gabarit, palette par défaut, échelle, clips
  templates/canid.usdz      # un fichier par gabarit, + canid.palette.json (rôles des cases)
  species/vulpes_vulpes.usdz  # modèles vedettes
  decor/…  islands/…
```

Les modèles non vedettes peuvent être téléchargés à la demande (On-Demand Resources ou CDN), pour ne pas alourdir l'app.

---

## Étape 3 — Isoler le moteur 3D dans le code Swift

**Choix du moteur.** Pour une refonte en 2026, **RealityKit** plutôt que SceneKit : SceneKit n'évolue plus, et Apple oriente les nouveaux développements vers RealityKit. RealityKit est aussi disponible en SwiftUI via `RealityView` (iOS 18 et plus). Si l'app actuelle est en SceneKit, l'isolation ci-dessous permet de migrer écran par écran.

**Architecture :**

```
FaunaDexApp (SwiftUI)
 ├─ Features/Capture, Dex, Fiche…       ← inchangés
 ├─ Features/Sanctuary/SanctuaryView    ← SwiftUI : overlay 2D + RealityView
 └─ Packages/SanctuaryEngine (Swift Package, aucune dépendance vers l'UI)
     ├─ SanctuaryEngine.swift        protocole : load(world:), spawn(species:palette:), setTime(_:), setWeather(_:)
     ├─ AssetCatalog.swift           lit catalog.json, charge et met en cache les USDZ (actor)
     ├─ PaletteRecolor.swift         texture-palette ← palette photo
     ├─ Systems/ (ECS RealityKit)    WanderSystem, AnimationSystem, DayNightSystem, WeatherSystem, SpawnFXSystem
     └─ Components/                  SpeciesComponent, WanderComponent, BiomeComponent…
```

```swift
public protocol SanctuaryEngine: AnyObject {
    func load(world: SanctuaryState) async throws
    func spawn(_ species: SpeciesID, palette: [Color], animated: Bool) async throws
    func setEnvironment(time: Date, weather: WeatherCondition, location: CLLocation?)
    var onTap: ((SanctuaryHit) -> Void)? { get set }   // animal, décor, vide
}
```

**Règles :**
- L'UI ne manipule jamais d'`Entity` directement ; elle passe par le protocole.
- Le moteur ne connaît ni SwiftUI ni la base de données. Il reçoit un `SanctuaryState` (animaux, décor, biomes).
- Remplacer un asset revient à changer une ligne de `catalog.json`.

---

## Étape 4 — Le Sanctuaire en diorama

**Principe.** Un archipel de **petites îles flottantes**, une par biome débloqué (Forêt, Prairie, Savane, Jungle, Montagne, Zone humide, Océan). Elles sont reliées par des ponts de bois, ou par des rivières qui tombent en cascade dans le vide.
- Chaque île est un **module** de 15 000 triangles au maximum, avec :
  - un socle de terre et de roche facetté visible sur les côtés (effet diorama coupé, à la Monument Valley) ;
  - 3 à 5 **emplacements** prévus pour le décor scanné (arbres, rochers) ;
  - un chemin de promenade, sous forme de spline, pour les animaux.
- **Déblocage.** Une île apparaît dès qu'on capture une espèce de ce biome, avec une animation d'émergence : elle monte des nuages en tournant légèrement. Cette logique existe déjà dans la maquette (biomes selon les espèces trouvées).
- **Caméra.** Une orbite douce autour de l'archipel, un zoom qui « plonge » sur une île, puis un suivi de l'animal touché. Pas de caméra libre : on reste dans un diorama.
- **Vue par défaut.** Légère plongée à environ 35°, avec une focale longue (35 à 50 mm équivalent) pour l'aspect maquette miniature. Un flou de profondeur léger est possible en option sur les appareils récents.

---

## Étape 5 — Lumière, ciel, jour/nuit et météo réels

- **Soleil réel.** Calculer l'élévation et l'azimut du soleil à partir de la position (CoreLocation) et de l'heure, avec un calcul astronomique standard (NOAA) côté app, sans réseau. Le `DirectionalLight` suit le soleil.
- **Palettes horaires.** On interpole ciel, soleil et ambiance entre des clés : aube `#FFD3A5`, jour `#BFE3FF`, heure dorée `#FFB77A`, crépuscule `#8C7BD1`, nuit `#1C2A4A`. Un dégradé de ciel peint (skybox) évite le rendu « ciel photo ».
- **Météo.** WeatherKit (ou l'API météo déjà utilisée pour les quêtes) fournit l'état :
  - pluie : particules, flaques brillantes, animaux qui s'abritent (déjà dans la maquette) ;
  - neige : couche blanche sur les faces qui regardent vers le haut, par une variante de matériau ;
  - brouillard : brume plus dense ;
  - vent : balancement des arbres par une légère déformation au shader.
- **Ombres.** Une seule lumière qui projette des ombres (le soleil), avec une cascade d'ombres limitée à l'archipel. La nuit, pas d'ombres portées et un éclairage d'ambiance bleuté. Les lucioles sont des points émissifs sans lumière réelle, ce qui ne coûte rien.

---

## Étape 6 — Particules d'ambiance

Utiliser le `ParticleEmitterComponent` de RealityKit, avec 1 ou 2 émetteurs actifs au maximum par île visible.

| Effet | Biome / condition | Détail |
|---|---|---|
| Feuilles qui tombent | Forêt, automne | Sprites de feuilles facettées, rotation lente |
| Lucioles | Nuit, zones humides et forêt | Points émissifs jaunes, clignotement |
| Pollen / pétales | Prairie, printemps | Très peu, dérive au vent |
| Embruns | Océan | Au pied des falaises |
| Poussière dorée | Savane, heure dorée | Accroche la lumière |
| Pluie / neige | Météo | Un émetteur qui suit la caméra |

---

## Étape 7 — Interface, transitions et apparition « waouh »

**Interface 2D :**
- **Cartes :**
  - coins arrondis (20 à 24 pt) ;
  - fond crème `#FBF7EF` ;
  - ombre douce et teintée plutôt que grise ;
  - une bande de couleur du biome en haut de chaque fiche.
- **Typographie.** Une grotesque ronde pour les titres (SF Pro Rounded, ou Bricolage Grotesque déjà utilisée dans la maquette) et SF Pro pour le texte. On reprend les couleurs d'accent de la charte.
- **Icônes.** Style facetté cohérent avec la 3D (SF Symbols en rendu hiérarchique, teinté par biome). Les badges peuvent devenir de petits objets 3D facettés, rendus en image.
- **Fiche animal.** Le modèle 3D tourne en haut de la fiche (petite `RealityView`) à la place de la photo seule. La photo reste accessible (« Ma photo »).

**Transitions** (SwiftUI `matchedGeometryEffect` + `PhaseAnimator` / `KeyframeAnimator`) :
1. Scanner → résultat : la photo se découpe en facettes triangulaires (shader Metal ou masque animé) qui se recomposent en carte d'espèce.
2. Carte → Dex : la carte rétrécit et vole vers sa case du Pokédex, avec un compteur qui s'incrémente.
3. Dex → Sanctuaire : fondu dans la vue 3D, et la caméra plonge vers l'île de l'espèce.

**Apparition « waouh »** (prototypée dans la maquette) :
1. Un œuf ou une capsule facettée tombe sur l'île et rebondit.
2. Elle se fend en triangles qui s'envolent.
3. L'animal jaillit avec un rebond (easeOutBack), accompagné d'un anneau lumineux au sol et d'étincelles.
4. L'animal joue son clip `happy`, avec un retour haptique (`UIImpactFeedbackGenerator`) et un son court.
5. Pour une espèce rare ou chromatique, on ajoute un halo coloré et une caméra qui tourne autour.

---

## Étape 8 — Performance : viser 60 FPS

**Budgets de scène :**
- 150 000 triangles visibles au maximum ;
- moins de 100 draw calls ;
- 1 ombre dynamique ;
- mémoire GPU sous 250 Mo sur iPhone 12.

**Leviers principaux :**
- **Un seul matériau par animal** (texture-palette) : un draw call chacun, et les instances partagent le même maillage.
- **Instanciation** du décor répétitif (herbes, fleurs, cailloux) : `MeshInstancesComponent` sur iOS 26 et plus, ou fusion des maillages par île sinon.
- **LOD.** Trois niveaux par animal (100 %, 40 %, 15 %, générés à l'export par Decimate). On bascule selon la distance, ou on remplace l'animal par un sprite quand il est tout petit à l'écran.
- **Animation.** Mettre en pause la mise à jour des animaux hors champ, et baisser la fréquence des animaux lointains.
- **Chargement.** Précharger les USDZ des espèces possédées au lancement, en asynchrone avec un acteur de cache. Charger les autres à la demande. Libérer les îles non visibles.
- **Mesure.** Instruments (RealityKit Trace, Metal System Trace), et un test de fumée qui échoue sous 55 FPS avec 60 animaux sur l'appareil de référence.

---

## Premiers pas concrets (semaine 1)

1. Valider la charte (étape 1) sur la maquette web : les animaux y sont déjà à facettes avec la lumière chaude. Ajuster la palette et la taille des facettes.
2. Choisir 5 espèces pilotes (renard, hibou, caméléon, cerf, mésange). Pour chacune, produire le pipeline complet de l'étape 2 : source, Blender, texture-palette, rig, clips, USDZ.
3. Créer le Swift Package `SanctuaryEngine` avec le protocole, et brancher l'écran Sanctuaire existant dessus (étape 3), avec les 5 USDZ.
4. Mesurer sur appareil : FPS, mémoire, temps de chargement. On ne passe à la production en série qu'après.
