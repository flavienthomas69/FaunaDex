# FaunaDex — Document de conception

> « Pokédex du vivant » : photographier un animal, l'identifier par IA, le capturer dans sa collection, consulter sa fiche, débloquer des badges.

Sommaire :
1. [Architecture globale et stack technique](#1-architecture-globale-et-stack-technique)
2. [Modèle de données](#2-modèle-de-données)
3. [Logique de déblocage des badges](#3-logique-de-déblocage-des-badges)
4. [Plan de développement du MVP](#4-plan-de-développement-du-mvp)
5. [Risques et points d'attention](#5-risques-et-points-dattention)

---

## 1. Architecture globale et stack technique

### 1.1 Vue d'ensemble

```
┌──────────────────────────┐        HTTPS/JSON         ┌───────────────────────────────┐
│  App mobile (Expo / RN)  │ ────────────────────────▶ │  API FaunaDex (TypeScript)    │
│  - Caméra / galerie      │                           │  - Auth (JWT Supabase)        │
│  - Collection hors-ligne │ ◀──────────────────────── │  - /observations (capture)    │
│  - Fiches, badges        │   résultat + badges       │  - Moteur de badges           │
└────────────┬─────────────┘                           └──────┬──────────┬─────────────┘
             │ upload direct (URL signée)                     │          │
             ▼                                                ▼          ▼
     ┌───────────────┐                          ┌─────────────────┐  ┌──────────────────────┐
     │ Stockage S3   │ ───── lecture image ───▶ │ Service Vision  │  │ PostgreSQL           │
     │ (photos)      │                          │ (Python, GPU)   │  │ users, taxons,       │
     └───────────────┘                          │ BioCLIP 2 +     │  │ captures, badges…    │
                                                │ filtre géo      │  └──────────────────────┘
                                                └─────────────────┘            ▲
                                                                               │ jobs asynchrones
                                                          ┌────────────────────┴───────────────┐
                                                          │ Pipeline de contenu (workers)      │
                                                          │ GBIF · Wikidata/Wikipedia · UICN   │
                                                          │ + rédaction assistée par LLM       │
                                                          └────────────────────────────────────┘
```

### 1.2 Frontend mobile

| Choix | Recommandation | Pourquoi |
|---|---|---|
| Framework | **React Native + Expo (SDK récent), TypeScript** | Une seule base iOS/Android, `expo-camera`, `expo-image-picker`, `expo-location`, builds et mises à jour OTA via EAS. |
| Navigation | Expo Router | Routage par fichiers, deep links vers une fiche (`/species/[id]`). |
| Données serveur | TanStack Query | Cache, retry, mode hors-ligne partiel. |
| État local | Zustand | Léger (file d'upload, préférences). |
| Cache hors-ligne | `expo-sqlite` | La collection et les fiches déjà débloquées restent consultables sans réseau. |
| Images | `expo-image` + `expo-image-manipulator` | Redimensionner à ~1024 px et compresser **avant** upload (coût, latence). |
| Animations | Reanimated + Lottie | L'effet « capture réussie / badge débloqué » est central dans l'expérience. |

Alternative : Flutter est tout aussi valable ; React Native est préféré ici pour partager TypeScript avec le backend.

### 1.3 Backend

**Recommandation MVP : Supabase (PostgreSQL managé + Auth + Storage) + une API TypeScript (Fastify ou NestJS).**

- **PostgreSQL** : les règles métier (unicité d'une capture, compteurs, badges) sont transactionnelles — une base relationnelle est le bon outil. Extensions utiles : `ltree` (arbre taxonomique), `pg_trgm` (recherche floue de noms), `postgis` (lieux d'observation).
- **Auth** : Supabase Auth (email, Apple, Google). Obligatoire : « Sign in with Apple » si un autre login social est proposé sur iOS.
- **Stockage** : bucket S3-compatible ; l'app uploade directement via une URL signée, l'API ne transporte jamais les octets de l'image.
- **API** : service TypeScript (Fastify) déployé sur Cloud Run / Fly.io. Il orchestre : upload → appel vision → validation → capture → badges. **La capture n'est jamais décidée par le client** (anti-triche).
- **Jobs asynchrones** : une file (pg-boss sur Postgres suffit au début) pour la génération de fiches, les notifications push (Expo Push), le recalcul de badges.

### 1.4 IA de vision

Couvrir tout le règne animal (≈ 1,5 million d'espèces décrites) exclut d'entraîner son propre modèle au départ. Stratégie recommandée, en couches :

1. **Modèle principal : BioCLIP 2** (open source, Imageomics, entraîné sur TreeOfLife — des centaines de milliers de taxons). Classification *zero-shot* sur l'arbre du vivant, auto-hébergeable sur GPU (Modal, RunPod, Replicate). Renvoie un top-k d'espèces avec scores.
2. **Filtre géographique (« geo-prior »)** : on repondère le top-k avec les données d'occurrence **GBIF** autour de la position GPS (ou du pays). Un kangourou photographié en Bretagne est rétrogradé. C'est le gain de précision le moins cher qui existe.
3. **Remontée taxonomique** : si la confiance au rang espèce est faible, on remonte au genre / à la famille (« Coccinelle — espèce incertaine »). L'utilisateur reçoit un résultat honnête et peut réessayer avec un meilleur angle.
4. **Vérification optionnelle par un LLM multimodal** (ex. Claude) pour : rejeter les images non valides (dessin, peluche, capture d'écran, pas d'animal), départager deux candidats proches, extraire des indices (« aile visible, vue dorsale »). Ne jamais l'utiliser seul pour nommer l'espèce : risque d'hallucination.
5. **Alternatives / compléments à évaluer** : API de vision d'iNaturalist (accès sur partenariat), Kindwise insect.id (insectes), SpeciesNet de Google (mammifères/oiseaux en pièges photo). L'interface `VisionProvider` côté service permet de brancher plusieurs moteurs.

Seuils de décision (à calibrer sur un jeu de test) :

| Confiance finale (après geo-prior) | Résultat |
|---|---|
| ≥ 0,80 au rang espèce | Capture validée automatiquement |
| 0,50 – 0,80 | L'utilisateur choisit parmi les 3 meilleures propositions (photos de référence à l'appui) |
| < 0,50 | Identification au genre/famille seulement, pas de capture d'espèce |

### 1.5 Contenu encyclopédique

Écrire 1,5 million de fiches à la main est impossible. Pipeline :

- **Taxonomie et noms** : GBIF Backbone Taxonomy (ou Catalogue of Life) → table `taxa`. Noms vernaculaires FR/EN via GBIF + **Wikidata**.
- **Texte** : résumé Wikipedia (CC BY-SA, attribution obligatoire) + données structurées Wikidata (taille, masse, longévité, aire de répartition) → **un LLM reformule en sections** (description, habitat, comportement, anecdotes) en s'appuyant *uniquement* sur ces sources, avec citation.
- **Statut de conservation** : UICN Red List API. ⚠️ Les conditions d'utilisation de l'UICN restreignent l'usage commercial : à valider juridiquement avant monétisation (Wikidata expose aussi le statut UICN, avec les mêmes réserves sur l'origine).
- **Stratégie de peuplement** : pré-générer des fiches complètes pour ~10 000 espèces « communes » (celles qu'on photographie réellement), et générer les autres **à la volée** lors de la première capture (fiche « en cours de rédaction » pendant quelques secondes).

---

## 2. Modèle de données

### 2.1 Principes

- **La taxonomie est un arbre** (Règne › Embranchement › Classe › Ordre › Famille › Genre › Espèce). On stocke tous les rangs dans une seule table `taxa` avec un chemin `ltree` → « toutes les espèces sous Aves » est une requête indexée.
- **Les catégories affichées ≠ la taxonomie.** « Poissons » ou « Reptiles » ne sont pas des groupes taxonomiques propres (paraphylétiques). Une table `categories` associe chaque catégorie de jeu à un ou plusieurs taxons racines ; chaque espèce reçoit une catégorie dénormalisée.
- **« Toute la famille » doit être un ensemble fini et atteignable.** Personne ne capturera le million d'espèces d'insectes. On introduit donc des **Dex** : listes curatées (« Oiseaux des jardins de France — 60 espèces », « Papillons d'Europe — 120 espèces ») sur lesquelles portent les badges de complétion.
- **Observation ≠ capture.** Chaque photo soumise crée une `observation` (historique, audit, ré-identification). Une `capture` est l'unique ligne « l'utilisateur possède cette espèce ».
- **Compteurs dénormalisés** pour que l'évaluation des badges soit en O(1), pas un `COUNT(*)` à chaque capture.

### 2.2 Schéma (PostgreSQL)

```sql
CREATE EXTENSION IF NOT EXISTS ltree;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ───────────── Utilisateurs ─────────────
CREATE TABLE users (
  id            uuid PRIMARY KEY,               -- = auth.users.id (Supabase)
  username      text UNIQUE NOT NULL,
  avatar_url    text,
  locale        text NOT NULL DEFAULT 'fr',
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ───────────── Taxonomie ─────────────
CREATE TYPE taxon_rank AS ENUM
  ('kingdom','phylum','class','order','family','genus','species','subspecies');

CREATE TABLE taxa (
  id               bigserial PRIMARY KEY,
  gbif_key         bigint UNIQUE,
  parent_id        bigint REFERENCES taxa(id),
  rank             taxon_rank NOT NULL,
  scientific_name  text NOT NULL,
  path             ltree NOT NULL,              -- ex. 'animalia.chordata.aves.passeriformes.paridae.parus.parus_major'
  category_id      int,                         -- dénormalisé, rempli pour les espèces
  rarity           smallint NOT NULL DEFAULT 1, -- 1 commun … 5 légendaire (dérivé occurrences GBIF + UICN)
  is_capturable    boolean NOT NULL DEFAULT false  -- vrai pour rank = species
);
CREATE INDEX taxa_path_gist ON taxa USING gist (path);
CREATE INDEX taxa_name_trgm ON taxa USING gin (scientific_name gin_trgm_ops);

CREATE TABLE taxon_common_names (
  taxon_id   bigint REFERENCES taxa(id) ON DELETE CASCADE,
  locale     text NOT NULL,
  name       text NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  PRIMARY KEY (taxon_id, locale, name)
);

-- ───────────── Catégories de jeu ─────────────
CREATE TABLE categories (
  id         serial PRIMARY KEY,
  code       text UNIQUE NOT NULL,              -- 'mammals', 'birds', 'insects', 'fish'…
  name_fr    text NOT NULL,
  icon       text,
  sort_order int NOT NULL DEFAULT 0
);
-- Une catégorie = un ou plusieurs sous-arbres taxonomiques
CREATE TABLE category_roots (
  category_id int    REFERENCES categories(id),
  taxon_id    bigint REFERENCES taxa(id),
  PRIMARY KEY (category_id, taxon_id)
);
ALTER TABLE taxa ADD FOREIGN KEY (category_id) REFERENCES categories(id);

-- ───────────── Fiches encyclopédiques ─────────────
CREATE TYPE conservation_status AS ENUM ('NE','DD','LC','NT','VU','EN','CR','EW','EX');

CREATE TABLE species_profiles (
  taxon_id        bigint REFERENCES taxa(id) ON DELETE CASCADE,
  locale          text NOT NULL,
  summary         text,
  key_facts       jsonb,        -- {"taille_cm":[12,14],"masse_g":[16,22],"longevite_ans":3,"regime":"insectivore"}
  habitat         text,
  distribution    text,
  range_geojson   jsonb,        -- aire de répartition simplifiée pour la carte
  behavior        text,
  anecdotes       text[],
  conservation    conservation_status,
  sources         jsonb NOT NULL DEFAULT '[]',  -- [{"type":"wikipedia","url":…,"license":"CC BY-SA 4.0"}]
  generation      text NOT NULL DEFAULT 'auto', -- 'auto' | 'reviewed' | 'manual'
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (taxon_id, locale)
);

CREATE TABLE species_media (
  id        bigserial PRIMARY KEY,
  taxon_id  bigint REFERENCES taxa(id),
  url       text NOT NULL,
  license   text NOT NULL,
  author    text,
  is_cover  boolean NOT NULL DEFAULT false
);

-- ───────────── Observations et captures ─────────────
CREATE TYPE observation_status AS ENUM
  ('pending','identified','needs_choice','uncertain','rejected');

CREATE TABLE observations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES users(id),
  photo_path         text NOT NULL,
  photo_phash        bigint,                    -- hash perceptuel (anti-doublon / anti-triche)
  source             text NOT NULL,             -- 'camera' | 'gallery'
  taken_at           timestamptz,               -- EXIF
  location           geography(Point, 4326),
  status             observation_status NOT NULL DEFAULT 'pending',
  predictions        jsonb,                     -- top-k brut du modèle + scores après geo-prior
  model_version      text,
  identified_taxon_id bigint REFERENCES taxa(id),
  confidence         real,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX observations_user ON observations (user_id, created_at DESC);
CREATE INDEX observations_phash ON observations (photo_phash);

CREATE TABLE captures (
  user_id               uuid   NOT NULL REFERENCES users(id),
  taxon_id              bigint NOT NULL REFERENCES taxa(id),
  first_observation_id  uuid   NOT NULL REFERENCES observations(id),
  best_observation_id   uuid   REFERENCES observations(id), -- photo affichée dans la collection
  captured_at           timestamptz NOT NULL DEFAULT now(),
  sightings_count       int NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, taxon_id)               -- une espèce = une capture par utilisateur
);

-- ───────────── Dex (collections finies) ─────────────
CREATE TABLE dex_sets (
  id           serial PRIMARY KEY,
  code         text UNIQUE NOT NULL,           -- 'birds_garden_fr'
  name_fr      text NOT NULL,
  category_id  int REFERENCES categories(id),
  region       text,                            -- 'FR', 'EU', NULL = monde
  species_count int NOT NULL DEFAULT 0          -- maintenu par trigger
);
CREATE TABLE dex_set_species (
  dex_set_id int    REFERENCES dex_sets(id) ON DELETE CASCADE,
  taxon_id   bigint REFERENCES taxa(id),
  PRIMARY KEY (dex_set_id, taxon_id)
);
CREATE INDEX dex_set_species_taxon ON dex_set_species (taxon_id);

-- ───────────── Compteurs de progression ─────────────
CREATE TABLE user_stats (
  user_id        uuid PRIMARY KEY REFERENCES users(id),
  total_species  int NOT NULL DEFAULT 0,
  total_sightings int NOT NULL DEFAULT 0,
  xp             int NOT NULL DEFAULT 0
);
CREATE TABLE user_category_stats (
  user_id      uuid REFERENCES users(id),
  category_id  int  REFERENCES categories(id),
  species_count int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, category_id)
);
CREATE TABLE user_dex_progress (
  user_id      uuid REFERENCES users(id),
  dex_set_id   int  REFERENCES dex_sets(id),
  captured     int NOT NULL DEFAULT 0,
  completed_at timestamptz,
  PRIMARY KEY (user_id, dex_set_id)
);

-- ───────────── Badges ─────────────
CREATE TYPE badge_rule AS ENUM (
  'total_species',      -- params: {"threshold": 50}
  'category_species',   -- params: {"category_id": 3, "threshold": 25}
  'dex_completion',     -- params: {"dex_set_id": 7, "percent": 100}
  'conservation',       -- params: {"statuses": ["EN","CR"], "threshold": 1}
  'rarity',             -- params: {"min_rarity": 5, "threshold": 1}
  'category_diversity', -- params: {"categories": 6}  (au moins 1 espèce dans 6 catégories)
  'zone_species',       -- params: {"zone_id": 1, "threshold": 25}      (cf. §2.4)
  'zone_diversity',     -- params: {"zones": 6}
  'fossil_count',       -- params: {"threshold": 5}                     (cf. §2.5)
  'museum_countries',   -- params: {"countries": 3}
  'micro_count'         -- params: {"threshold": 5}                     (cf. §2.6)
);

CREATE TABLE badges (
  id          serial PRIMARY KEY,
  code        text UNIQUE NOT NULL,             -- 'total_100', 'birds_25', 'dex_birds_garden_fr'
  name_fr     text NOT NULL,
  description_fr text NOT NULL,
  icon        text NOT NULL,
  tier        text NOT NULL DEFAULT 'bronze',   -- bronze | argent | or | platine
  rule        badge_rule NOT NULL,
  params      jsonb NOT NULL,
  -- clés d'indexation extraites de params pour ne charger que les badges concernés
  category_id int REFERENCES categories(id),
  dex_set_id  int REFERENCES dex_sets(id),
  xp_reward   int NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true
);
CREATE INDEX badges_rule ON badges (rule) WHERE is_active;

CREATE TABLE user_badges (
  user_id        uuid REFERENCES users(id),
  badge_id       int  REFERENCES badges(id),
  unlocked_at    timestamptz NOT NULL DEFAULT now(),
  observation_id uuid REFERENCES observations(id), -- la capture qui l'a déclenché
  seen           boolean NOT NULL DEFAULT false,   -- pour l'animation « nouveau badge »
  PRIMARY KEY (user_id, badge_id)                   -- idempotence
);
```

### 2.3 Catalogue de badges initial

| Type | Exemples | Règle |
|---|---|---|
| Volume | Premier pas (1), Explorateur (10), Naturaliste (25), Biologiste (50), Centurion (100), 200, 500, 1000 | `total_species ≥ seuil` |
| Catégorie — paliers | Ornithologue bronze/argent/or (5 / 25 / 100 oiseaux), Entomologiste (insectes), Herpétologue (reptiles + amphibiens), Arachnologue… | `category_species ≥ seuil` |
| Catégorie — complétion | « Oiseaux des jardins : 100 % », « Papillons de France : 50 % / 100 % » | `dex_completion` sur un Dex fini |
| Diversité | Arche de Noé (au moins 1 espèce dans 8 catégories) | `category_diversity` |
| Conservation | Gardien (1 espèce menacée VU/EN/CR photographiée à l'état sauvage) | `conservation` |
| Rareté | Chanceux (1 espèce de rareté 5) | `rarity` |

Catégories initiales proposées : Mammifères, Oiseaux, Reptiles, Amphibiens, Poissons, Insectes, Arachnides, Crustacés, Mollusques, Autres invertébrés (vers, méduses, échinodermes…).

### 2.4 Zones géographiques

Le joueur peut parcourir sa collection **par zone** (France, Europe, Afrique, Océans…), comme un Pokédex régional. Une zone regroupe les espèces dont **l'aire de répartition** la couvre ; le lieu où la photo a été prise est une autre information, stockée dans `observations.location`.

```sql
CREATE TABLE zones (
  id        serial PRIMARY KEY,
  code      text UNIQUE NOT NULL,      -- 'fr', 'eu', 'af', 'mer'…
  name_fr   text NOT NULL,
  kind      text NOT NULL,             -- 'continent' | 'ocean' | 'country' | 'region'
  parent_id int REFERENCES zones(id),  -- France → Europe
  geom      geography(MultiPolygon, 4326)
);

CREATE TABLE taxon_zones (
  taxon_id  bigint REFERENCES taxa(id) ON DELETE CASCADE,
  zone_id   int    REFERENCES zones(id),
  status    text NOT NULL DEFAULT 'native',  -- 'native' | 'introduced' | 'vagrant'
  source    text NOT NULL,                   -- 'mdd' | 'gbif_occurrences' | 'iucn_range'
  PRIMARY KEY (taxon_id, zone_id)
);
CREATE INDEX taxon_zones_zone ON taxon_zones (zone_id);

CREATE TABLE user_zone_stats (
  user_id       uuid REFERENCES users(id),
  zone_id       int  REFERENCES zones(id),
  species_count int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, zone_id)
);
```

Sources de répartition, par ordre de préférence :
1. **Listes de référence par groupe** : Mammal Diversity Database pour les mammifères (continents et pays, CC BY 4.0), cartes de l'UICN quand la licence le permet.
2. **Occurrences GBIF** pour tous les autres groupes : une espèce est rattachée à une zone si elle y compte un nombre minimal d'observations validées (par exemple 5, hors spécimens de zoo ou de musée). Le calcul se fait par lots avec l'API d'agrégats GBIF, puis il est rafraîchi chaque trimestre.

Chaque capture incrémente `user_zone_stats` pour toutes les zones de l'espèce, dans la même transaction que les autres compteurs (§3.3). Deux nouvelles règles de badges s'appuient dessus : `zone_species` (« Faune de France : 25 espèces présentes en France ») et `zone_diversity` (« Globe-trotter : des espèces de 6 zones du monde »).

### 2.5 Paléo-Dex : les dinosaures

Un onglet à part recense les dinosaures. On ne les rencontre pas vivants : **on les capture en photographiant leur squelette exposé dans un musée**. Seuls les dinosaures dont un squelette est exposé et répertorié peuvent donc être capturés, et l'application indique dans quels musées aller.

```sql
CREATE TABLE museums (
  id        serial PRIMARY KEY,
  name      text NOT NULL,
  city      text NOT NULL,
  country   text NOT NULL,
  location  geography(Point, 4326) NOT NULL,
  geofence_m int NOT NULL DEFAULT 250            -- rayon dans lequel la photo doit être prise
);

-- Un squelette exposé : original ou moulage, dans un musée donné
CREATE TABLE skeleton_exhibits (
  id            serial PRIMARY KEY,
  taxon_id      bigint NOT NULL REFERENCES taxa(id),   -- espèce fossile (taxa.is_extinct = true)
  museum_id     int    NOT NULL REFERENCES museums(id),
  specimen      text,                                  -- « Sue », « Sophie », numéro d'inventaire…
  is_cast       boolean NOT NULL DEFAULT false,        -- moulage plutôt que les os originaux
  gallery       text,                                  -- salle où il est exposé
  is_active     boolean NOT NULL DEFAULT true          -- retiré, prêté, en restauration…
);

-- Photos de référence de chaque squelette pour la reconnaissance
CREATE TABLE exhibit_reference_images (
  exhibit_id  int REFERENCES skeleton_exhibits(id) ON DELETE CASCADE,
  image_path  text NOT NULL,
  embedding   vector(768)                            -- extension pgvector
);

ALTER TABLE taxa ADD COLUMN is_extinct boolean NOT NULL DEFAULT false;
ALTER TABLE captures ADD COLUMN exhibit_id int REFERENCES skeleton_exhibits(id);
```

Reconnaissance d'un squelette (flux distinct du vivant) :
1. **Position** : la photo doit être prise dans le périmètre d'un musée connu (`geofence_m`), ce qui réduit les candidats aux squelettes exposés dans ce musée, souvent moins de dix.
2. **Correspondance d'image** : l'embedding de la photo est comparé aux photos de référence de ces squelettes. Un squelette monté est un objet fixe, donc une recherche par similarité suffit, sans modèle d'espèce.
3. **Cartel** : si le cartel du musée est dans le cadre, sa lecture par OCR confirme le nom.
4. Une capture fossile n'est valide que si le squelette est `is_active`. Les photos importées de la galerie sans position de musée sont refusées, ce qui empêche de capturer un dinosaure depuis une image trouvée en ligne.

Contenu du référentiel : partir d'une liste curatée de squelettes célèbres (Sue à Chicago, Sophie à Londres, le Diplodocus de Paris…), puis l'enrichir avec Wikidata, qui décrit de nombreux spécimens avec leur musée (propriétés « collection » et « lieu d'exposition »), et avec les musées partenaires. Badges dédiés : `fossil_count` (1, 5, tout le Paléo-Dex) et `museum_countries` (squelettes photographiés dans 3 pays).

### 2.6 Micro-Dex : le monde microscopique

Un troisième onglet recense ce qu'on trouve au microscope dans une goutte d'eau de mare, une touffe de mousse ou de la poussière : animaux microscopiques (tardigrades, rotifères, nématodes, daphnies, acariens…) et, parce qu'on les croise dans les mêmes prélèvements, des protistes (paramécies, amibes, vorticelles) et des algues (diatomées, volvox). Ces derniers ne sont pas des animaux, ce que la fiche indique.

Données :
- Liste curatée d'organismes courants (`micro_dex_entries` : taxon, groupe, taille, grossissement conseillé, habitat de prélèvement, méthode). Les protistes et les algues sortent du règne Animalia : l'import GBIF (`services/catalog`) doit alors inclure aussi les taxons listés des règnes Protozoa, Chromista et Plantae.
- L'identification se fait souvent au **genre** (« *Vorticella* sp. ») : c'est le niveau réaliste pour une photo au microscope, et la remontée taxonomique du §1.4 s'applique.

Capture en mode microscope :
1. La photo doit être prise par l'appareil photo de l'app, à travers l'oculaire ou avec une lentille macro. Le service de vision vérifie la présence du **champ circulaire de l'oculaire** (disque éclairé sur fond noir), ce qui écarte la plupart des images récupérées sur Internet.
2. Le modèle estime le grossissement à partir de la taille apparente, et rejette une identification incohérente (une daphnie de 2 mm ne remplit pas le champ à ×400).
3. Le **lieu du prélèvement** (position au moment de la photo) est enregistré. Le contrôle anti-captivité (`services/captivity`) ne s'applique pas : un prélèvement de mare est par nature sauvage.

Badges dédiés : `micro_count` (1, 5, tout le Micro-Dex) et des badges d'espèce emblématique (« Chasseur d'oursons d'eau » pour un tardigrade).

### 2.7 Rareté et variantes « shiny »

**Rareté** : chaque capture reçoit un niveau (Commun, Rare, Épique, Légendaire), le plus élevé de deux indices.
- *Indice local* : part de l'espèce dans les observations GBIF de la maille de 50 km où la photo est prise, sur les 5 dernières années. Plus de 1 % des observations : commun ; 0,1–1 % : rare ; 0,01–0,1 % : épique ; en dessous : légendaire. Une mésange est commune à Lyon, une grue cendrée y est épique mais commune au lac du Der en novembre.
- *Indice de conservation* : UICN quasi menacée → au moins rare, vulnérable → au moins épique, en danger ou en danger critique → légendaire.
- XP de base : 10 / 25 / 60 / 150. Le calcul se fait à la capture et reste figé dans `captures.rarity`, pour que la valeur d'une capture ne change pas quand les données GBIF évoluent.

**Variantes** : albinisme, leucisme, mélanisme, plumage nuptial, comportements rares (parade, nourrissage, chasse…). La liste possible dépend du groupe (et peut être surchargée par espèce).
- Détection par un classifieur d'attributs sur la photo, puis **validation communautaire** (deux validateurs confirmés) avant d'accorder le bonus ×2, car c'est la récompense la plus exposée à la triche.

```sql
CREATE TABLE taxon_variants (
  taxon_id  bigint REFERENCES taxa(id),
  code      text NOT NULL,             -- 'leucism', 'breeding_plumage', 'courtship'…
  kind      text NOT NULL,             -- 'color' | 'seasonal' | 'behavior'
  name_fr   text NOT NULL,
  PRIMARY KEY (taxon_id, code)
);
ALTER TABLE captures ADD COLUMN rarity smallint NOT NULL DEFAULT 0;
CREATE TABLE capture_variants (
  user_id        uuid,
  taxon_id       bigint,
  variant_code   text,
  observation_id uuid REFERENCES observations(id),
  status         text NOT NULL DEFAULT 'pending',  -- 'pending' | 'validated' | 'rejected'
  PRIMARY KEY (user_id, taxon_id, variant_code)
);
```

### 2.8 Carte, brouillard de guerre et hotspots

- **Navigation** : carte glissable et zoomable (MapLibre sur mobile, tuiles vectorielles rendues par le GPU), bouton « autour de moi » et vue d'ensemble ; les noms des lieux d'observation apparaissent en zoomant. Le brouillard est une couche à part, dessinée en dégradé autour des cellules explorées, et non un filtre de flou, qui ralentit fortement le zoom.
- **Environnements par région** : chaque zone de la carte a son style (forêt tempérée, forêt boréale, forêt tropicale, campagne, savane, steppe, désert, montagne, toundra, glaces, ville, littoral), avec un motif propre : arbres, champs, dunes, sommets, pâtés de maisons, vagues. La maquette les calcule à partir de données réelles (zones urbaines, glaciers, déserts et massifs de Natural Earth) et de règles climatiques simples ; l'application utilisera une vraie carte d'occupation des sols (ESA WorldCover à 10 m, ou Corine Land Cover en Europe). L'environnement du lieu de capture est enregistré et alimente la légende « environnements découverts ».
- **Fond des zones découvertes** : sous le brouillard, un style cartographique riche (relief et massifs, forêts, fleuves, lacs, villes, noms) n'apparaît que dans les cellules explorées. La maquette l'obtient avec Natural Earth (domaine public) ; l'application utilisera un style de tuiles vectorielles OpenStreetMap avec relief ombré.
- **Brouillard** : la carte est couverte, sauf dans un rayon de 40 km autour de chaque lieu d'observation du joueur. Stockage : cellules H3 de résolution 5 (≈ 250 km²) dans `user_explored_cells (user_id, h3_cell)`, remplies à chaque capture. Le client ne reçoit que les cellules, jamais les coordonnées des autres joueurs.
- **Hotspots** : agrégats par maille de 50 km et par famille, recalculés chaque nuit. Règles de protection : au moins 5 observateurs distincts, délai d'une semaine, exclusion de toute espèce UICN vulnérable ou plus et des listes d'espèces sensibles (rapaces nicheurs, chiroptères en gîte…). La position exacte d'une observation n'est jamais exposée.

### 2.9 Quêtes, événements et bonus météo

- **Quêtes** : définitions en base (`quests` : période, règle en JSON, récompense), progression calculée à partir du journal des captures, comme les badges (§3). Types : quotidiennes (renouvelées à 4 h, heure locale), hebdomadaires, saisonnières.
- **Événements** : fenêtres datées (« Grande migration d'automne » du 22 septembre au 21 décembre) qui ajoutent des quêtes et des multiplicateurs (×2 sur les migrateurs, liste tirée des traits d'espèce).
- **Heure et météo** : calculées côté serveur à partir de la position et de l'heure de la photo. La nuit est définie par le coucher et le lever du soleil au lieu de la capture ; la météo vient d'une API météo historique (Open-Meteo, par exemple). Bonus : +50 % pour une espèce nocturne photographiée de nuit, +50 % sous la pluie. Le client ne déclare jamais ces conditions lui-même.

### 2.10 Compagnon, sanctuaire et météo-morphisme

- **Œuf et compagnon** : à l'inscription, un œuf mystère éclot après 3 captures ; le joueur choisit alors un compagnon (renardeau, chouette ou lézard). Il gagne la même XP que le joueur et évolue en trois stades (niveaux 1, 4 et 8).
- **Sanctuaire** : chaque espèce capturée y apparaît sous forme animée. Le joueur choisit un biome (forêt, savane, océan, jungle). Il nourrit ses animaux avec des ressources gagnées en photographiant des animaux et en scannant des plantes (identification végétale, par exemple avec l'API Pl@ntNet ; les plantes ne comptent pas dans la collection).
- **Météo-morphisme** : le sanctuaire reprend la météo réelle du joueur (position approximative, au kilomètre près, rafraîchie toutes les 30 minutes). Sous la pluie, les amphibiens et les escargots sortent et les autres s'abritent ; la nuit, seuls les animaux nocturnes restent actifs. Le comportement de chaque animal dépend de ses traits (`nocturnal`, `likes_rain`…).

```sql
CREATE TABLE companions (
  user_id    uuid PRIMARY KEY REFERENCES users(id),
  kind       text,                        -- NULL tant que l'œuf n'a pas éclos
  egg_progress smallint NOT NULL DEFAULT 0,
  xp         int NOT NULL DEFAULT 0,
  hatched_at timestamptz
);
CREATE TABLE sanctuaries (
  user_id    uuid PRIMARY KEY REFERENCES users(id),
  biome      text NOT NULL DEFAULT 'forest',
  food       int NOT NULL DEFAULT 0,
  wellbeing  smallint NOT NULL DEFAULT 50
);
CREATE TABLE taxon_traits (
  taxon_id   bigint REFERENCES taxa(id),
  trait      text NOT NULL,               -- 'nocturnal' | 'likes_rain' | 'pollinator' | 'migratory'…
  PRIMARY KEY (taxon_id, trait)
);
```

### 2.11 Sanctuaire 3D et modélisation à partir de la photo

**Monde navigable.** Le sanctuaire est une île en 3D : on tourne autour (un doigt), on se déplace (deux doigts), on zoome (pincer) et on touche un animal ou un élément pour l'inspecter. Sur mobile : `expo-gl` + `@react-three/fiber/native` ; la maquette utilise three.js dans le navigateur.

**Décor à construire.** L'île est vide au départ. Un mode « Décor » de l'appareil photo ajoute ce que le joueur scanne dans la vraie vie :

| Élément scanné | Identification | Ce qui est repris de la photo |
|---|---|---|
| Rocher | Classifieur de textures (granite, calcaire, grès, basalte…) | Couleur, forme générale |
| Arbre, buisson, fleurs | Identification végétale (Pl@ntNet) | Essence → silhouette (conifère, feuillu), couleur du feuillage ; rapporte de la nourriture |
| Montagne | Position + boussole + modèle numérique de terrain pour nommer le sommet visé | Silhouette, enneigement |
| Plan d'eau | Classifieur (mare, étang, ruisseau) | Couleur de l'eau ; permet d'accueillir poissons et animaux aquatiques |

**Modéliser l'animal à partir de la photo.** Objectif : que le chat roux photographié ressemble à *ce* chat roux, tout en restant animable.
1. **Segmentation** de l'animal sur la photo (modèle de type Segment Anything) côté serveur.
2. **Gabarit** : l'espèce (ou sa famille) donne un modèle 3D riggé parmi une bibliothèque d'environ 15 plans d'organisation : quadrupède, oiseau percheur, oiseau échassier, insecte volant, coléoptère, araignée, lézard, tortue, grenouille, poisson, escargot, pieuvre, crabe… Une table de proportions par espèce ajuste le gabarit (taille des oreilles, longueur des pattes, queue touffue…).
3. **Transfert d'apparence** : les couleurs dominantes de la zone segmentée sont affectées aux zones du gabarit (dos, ventre, tête, queue, pattes). Pour les motifs (tigré, taches, rayures), la photo est projetée sur la texture du modèle depuis l'angle de prise de vue, et les zones non visibles sont complétées par symétrie.
4. **Option haut de gamme** : reconstruction 3D à partir d'une seule image (modèles de type TripoSR ou Stable Fast 3D) pour les éléments fixes du décor comme les rochers, où l'animation n'est pas nécessaire.
5. Le résultat est stocké en glTF par capture (`captures.model_url`) et régénéré si le joueur fournit une meilleure photo.

**Squelettes.** Les vertébrés ont un corps continu déformé par une chaîne d'os (skinning) : colonne, cou, tête et queue pour les mammifères, les lézards et les poissons ; épaule, coude et poignet pour les ailes, qui se replient au repos et battent en vol ; hanche, genou (ou jarret) et cheville pour chaque patte, avec une démarche en diagonale. Les arthropodes ont des pattes à trois articulations (hanche, fémur, tibia) et marchent en tripode ; le crabe marche de côté ; la grenouille saute en dépliant ses pattes arrière ; les bras de la pieuvre ondulent. Au repos, les animaux broutent, regardent autour d'eux et respirent.

La maquette applique déjà les étapes 2 et 3 de façon simplifiée : un gabarit procédural par groupe (corps modelé, pattes articulées qui marchent, ailes et nageoires animées, textures de fourrure, plumes ou écailles), coloré avec les deux couleurs dominantes du centre de la photo importée. En production, ces gabarits sont remplacés par des modèles sculptés et riggés par un artiste 3D, puis texturés à partir de la photo.

**Biomes du sanctuaire.** L'île se découpe en secteurs selon l'habitat des espèces trouvées : forêt, prairie, zone humide, montagne, garrigue, savane, littoral. Un biome apparaît dès qu'on capture une espèce qui y vit (table `taxon_habitats`, déduite de l'UICN et de GBIF). Des rivières séparent les secteurs et rejoignent un lac central ; le littoral ouvre sur une baie où vivent les espèces marines. Chaque biome a son relief (collines et rochers en montagne, sol bas et mares en zone humide, baie sableuse sur le littoral) et sa végétation (fougères et champignons, fleurs, roseaux et nénuphars, arbustes, herbes sèches). Les éléments scannés se placent de préférence dans le biome qui leur correspond, et chaque animal reste dans le sien.

**Gabarits par ordre et famille.** Pour le catalogue complet, le gabarit dépend de l'ordre et de la famille : ongulés à sabots avec cornes (enroulées pour les moutons, arrière pour les chèvres, latérales pour les bovins) ou bois (cervidés), laine pour les moutons, félins, ours, mustélidés, lapins à longues oreilles, rongeurs, primates, éléphants (trompe, oreilles, défenses), chauves-souris (vol), cétacés (nageoire caudale horizontale) et phoques (nage).

**Comportements.** Chaque animal erre, vole ou nage selon ses traits ; il faut un plan d'eau pour que les espèces aquatiques apparaissent. La nuit, seuls les animaux nocturnes restent actifs ; sous la pluie, les autres rejoignent l'abri des arbres scannés.

**Direction artistique.** Le rendu est « low-poly » à facettes, avec des aplats de couleur nets et sans textures bruitées. Quand un modèle animé réalisé par un artiste existe, on l'utilise :
- renard articulé avec les animations attente, marche et course, aussi utilisé pour le loup et les autres canidés ;
- cheval pour les équidés ;
- oiseau en vol pour les passereaux ;
- cigogne pour les hérons, cigognes et grues ;
- flamant.

Ces modèles sont recolorés avec les couleurs de la photo : chaque teinte du modèle est rangée en sombre, clair ou couleur dominante, puis remplacée par la couleur correspondante de la palette extraite. Les autres espèces gardent leur gabarit procédural, dans le même style à facettes. Les arbres et rochers scannés utilisent le Nature Kit de Kenney (CC0), recoloré selon le scan. Les crédits et licences sont dans `maquette/models/LICENCES.md`. En production, la bibliothèque de modèles serait étendue famille par famille (modèles commandés ou sous licence CC0 ou CC-BY).

---

## 3. Logique de déblocage des badges

### 3.1 Principes

1. **Côté serveur uniquement**, dans la **même transaction** que la capture : pas d'état incohérent (capture sans badge, ou badge sans capture).
2. **Seule une nouvelle espèce** fait progresser les badges d'espèces. Revoir une mésange déjà capturée incrémente `sightings_count`, rien de plus.
3. **Évaluation incrémentale** : on ne réévalue que les badges touchés par les dimensions qui viennent de changer (le total, *la* catégorie de l'espèce, *les* Dex qui la contiennent). Avec les compteurs dénormalisés, c'est une poignée de comparaisons d'entiers.
4. **Idempotence** : `INSERT … ON CONFLICT DO NOTHING RETURNING` sur `user_badges`. Un retry réseau ou un double-tap ne donne jamais deux fois le même badge.
5. **Rétroactivité** : quand on crée un nouveau badge (ou un nouveau Dex), un job de rattrapage l'évalue pour tous les utilisateurs à partir des compteurs.

### 3.2 Flux complet d'une capture

```
App                         API                             Vision            Postgres
 │ 1. POST /uploads ────────▶│ URL signée                      │                  │
 │ 2. PUT photo ──────────────────────────────────▶ S3          │                  │
 │ 3. POST /observations ───▶│ insert observation(pending) ─────────────────────▶ │
 │                           │ 4. identify(photo, gps) ───────▶│                  │
 │                           │ ◀────────── top-k + scores ─────│                  │
 │                           │ 5. geo-prior + seuils            │                  │
 │                           │ 6. si ≥ seuil : TRANSACTION capture + badges ────▶ │
 │ ◀── {species, isNew, newBadges[], progress} ──│              │                  │
 │ 7. animation capture / badge                                                    │
```

**Contrôle anti-captivité**, entre les étapes 3 et 4 : l'API vérifie avec `captivity_check` que la photo n'a pas été prise dans un zoo, un aquarium ou un parc animalier (contours OpenStreetMap dans PostGIS). Une photo sans position, trop imprécise ou prise dans un de ces lieux est refusée avant même l'identification, et un déclencheur en base empêche toute capture qui n'aurait pas passé ce contrôle. Règles et code : `services/captivity/`.

Si la confiance est intermédiaire, l'étape 6 est déclenchée par `POST /observations/:id/confirm { taxonId }`, en vérifiant que `taxonId` fait bien partie du top-k renvoyé par le modèle (le client ne peut pas inventer une espèce).

### 3.3 Implémentation (TypeScript, service API)

```ts
// capture.service.ts
import type { PoolClient } from 'pg';

export interface CaptureResult {
  taxonId: number;
  isNewSpecies: boolean;
  newBadges: UnlockedBadge[];
  progress: { totalSpecies: number; categorySpecies: number; dex: DexProgress[] };
}

export async function recordCapture(
  db: PoolClient,
  userId: string,
  observationId: string,
  taxonId: number,
): Promise<CaptureResult> {
  await db.query('BEGIN');
  try {
    // 1. Tenter la capture. RETURNING ne renvoie une ligne que si l'espèce est nouvelle.
    const inserted = await db.query(
      `INSERT INTO captures (user_id, taxon_id, first_observation_id, best_observation_id)
       VALUES ($1, $2, $3, $3)
       ON CONFLICT (user_id, taxon_id) DO NOTHING
       RETURNING taxon_id`,
      [userId, taxonId, observationId],
    );
    const isNewSpecies = inserted.rowCount === 1;

    if (!isNewSpecies) {
      await db.query(
        `UPDATE captures SET sightings_count = sightings_count + 1
         WHERE user_id = $1 AND taxon_id = $2`,
        [userId, taxonId],
      );
      await db.query(
        `UPDATE user_stats SET total_sightings = total_sightings + 1 WHERE user_id = $1`,
        [userId],
      );
      await db.query('COMMIT');
      return { taxonId, isNewSpecies, newBadges: [], progress: await readProgress(db, userId, taxonId) };
    }

    // 2. Mettre à jour les compteurs (une seule ligne verrouillée par dimension).
    const { rows: [taxon] } = await db.query(
      `SELECT category_id, rarity, sp.conservation
       FROM taxa t LEFT JOIN species_profiles sp ON sp.taxon_id = t.id AND sp.locale = 'fr'
       WHERE t.id = $1`,
      [taxonId],
    );

    const { rows: [stats] } = await db.query(
      `INSERT INTO user_stats (user_id, total_species, total_sightings) VALUES ($1, 1, 1)
       ON CONFLICT (user_id) DO UPDATE
         SET total_species = user_stats.total_species + 1,
             total_sightings = user_stats.total_sightings + 1
       RETURNING total_species`,
      [userId],
    );

    const { rows: [cat] } = await db.query(
      `INSERT INTO user_category_stats (user_id, category_id, species_count) VALUES ($1, $2, 1)
       ON CONFLICT (user_id, category_id) DO UPDATE
         SET species_count = user_category_stats.species_count + 1
       RETURNING species_count`,
      [userId, taxon.category_id],
    );

    const { rows: dexRows } = await db.query(
      `INSERT INTO user_dex_progress (user_id, dex_set_id, captured)
       SELECT $1, dss.dex_set_id, 1 FROM dex_set_species dss WHERE dss.taxon_id = $2
       ON CONFLICT (user_id, dex_set_id) DO UPDATE
         SET captured = user_dex_progress.captured + 1
       RETURNING dex_set_id, captured`,
      [userId, taxonId],
    );

    // 3. Évaluer uniquement les badges candidats, en une requête.
    const { rows: newBadges } = await db.query(
      `WITH ctx AS (
         SELECT $2::int AS total, $3::int AS cat_id, $4::int AS cat_count,
                $5::int AS rarity, $6::text AS status
       ),
       dex AS (
         SELECT d.id, p.captured, d.species_count
         FROM user_dex_progress p JOIN dex_sets d ON d.id = p.dex_set_id
         WHERE p.user_id = $1 AND p.dex_set_id = ANY($7::int[])
       ),
       eligible AS (
         SELECT b.id FROM badges b, ctx
         WHERE b.is_active AND (
              (b.rule = 'total_species'    AND ctx.total     >= (b.params->>'threshold')::int)
           OR (b.rule = 'category_species' AND b.category_id = ctx.cat_id
                                           AND ctx.cat_count >= (b.params->>'threshold')::int)
           OR (b.rule = 'rarity'           AND ctx.rarity    >= (b.params->>'min_rarity')::int)
           OR (b.rule = 'conservation'     AND ctx.status = ANY (
                 ARRAY(SELECT jsonb_array_elements_text(b.params->'statuses'))))
           OR (b.rule = 'dex_completion'   AND EXISTS (
                 SELECT 1 FROM dex WHERE dex.id = b.dex_set_id
                   AND dex.captured * 100 >= dex.species_count * (b.params->>'percent')::int))
           OR (b.rule = 'category_diversity' AND
                 (SELECT count(*) FROM user_category_stats
                  WHERE user_id = $1 AND species_count > 0) >= (b.params->>'categories')::int)
         )
       )
       INSERT INTO user_badges (user_id, badge_id, observation_id)
       SELECT $1, id, $8 FROM eligible
       ON CONFLICT (user_id, badge_id) DO NOTHING
       RETURNING badge_id`,
      [userId, stats.total_species, taxon.category_id, cat.species_count,
       taxon.rarity, taxon.conservation, dexRows.map(r => r.dex_set_id), observationId],
    );

    // 4. XP + marquage des Dex complétés + événement pour les notifications push.
    await applyRewards(db, userId, taxon, newBadges.map(b => b.badge_id));
    await markCompletedDex(db, userId, dexRows);
    await enqueueOutbox(db, 'capture.created', { userId, taxonId, badgeIds: newBadges.map(b => b.badge_id) });

    await db.query('COMMIT');
    return {
      taxonId,
      isNewSpecies,
      newBadges: await loadBadges(db, newBadges.map(b => b.badge_id)),
      progress: await readProgress(db, userId, taxonId),
    };
  } catch (e) {
    await db.query('ROLLBACK');
    throw e;
  }
}
```

Remarques :

- Les seuils « déjà dépassés » sont naturellement filtrés par `ON CONFLICT DO NOTHING` : seuls les badges **nouvellement** débloqués reviennent dans `RETURNING`, ce qui pilote l'animation côté app.
- Les `INSERT … ON CONFLICT DO UPDATE` sur les compteurs verrouillent la ligne concernée : deux captures simultanées du même utilisateur ne peuvent pas produire un compteur faux.
- Le badge `conservation` peut être restreint aux photos prises à l'état sauvage (`source = 'camera'` + zone hors zoo connue) pour garder du sens.
- **Rattrapage** (nouveau badge publié) : un job exécute la même clause `eligible` en mode ensembliste sur `user_stats` / `user_category_stats` / `user_dex_progress` pour tous les utilisateurs, avec `observation_id = NULL`.
- **Retrait d'une capture** (modération, fraude) : décrémenter les compteurs dans une transaction et, par choix produit, **ne pas** retirer les badges déjà obtenus sauf fraude avérée.

### 3.4 Progression affichée

Pour les barres de progression (« Ornithologue argent : 18 / 25 »), une requête `GET /me/badges` joint `badges` aux compteurs et renvoie pour chaque badge non obtenu `current` et `target`. Aucune logique de calcul dupliquée côté client.

---

## 4. Plan de développement du MVP

Objectif du MVP : **prouver la boucle photo → identification fiable → capture → fiche → badge**, sur un périmètre géographique restreint (France / Europe de l'Ouest) tout en acceptant n'importe quel animal.

### Phase 0 — Validation technique (1–2 semaines) ⚠️ la plus importante
- Constituer un jeu de test de ~500 photos réelles (smartphone, conditions réelles) couvrant les 10 catégories.
- Mesurer la précision top-1 / top-3 de BioCLIP 2, avec et sans geo-prior GBIF, et d'une ou deux alternatives.
- Mesurer latence et coût par identification sur GPU serverless.
- **Critère de sortie** : ≥ 80 % top-3 au rang espèce sur les espèces communes, < 4 s de bout en bout. Sinon, revoir le fournisseur avant d'écrire l'app.

### Phase 1 — Fondations (2 semaines)
- Monorepo : `apps/mobile` (Expo), `services/api` (Fastify), `services/vision` (Python/FastAPI), `packages/shared` (types, schémas zod).
- Supabase : projet, auth (email + Apple + Google), bucket photos, migrations SQL (schéma ci-dessus).
- Import taxonomique GBIF (règne Animalia) + noms FR/EN + catégories et `category_roots`.
- CI : lint, typecheck, tests, migrations.

### Phase 2 — Boucle de capture (3 semaines)
- Écran caméra + import galerie, compression, lecture EXIF/GPS (avec consentement).
- Upload signé → `POST /observations` → service vision → résultat.
- Écran résultat : validé / choix parmi 3 / incertain.
- `recordCapture` transactionnel + tests d'intégration (nouvelle espèce, doublon, concurrence).

### Phase 3 — Fiches et collection (2 semaines)
- Pipeline de contenu : Wikidata + Wikipedia + UICN → LLM → `species_profiles`, pré-généré pour ~2 000 espèces communes d'Europe, à la volée pour les autres.
- Écran fiche (nom commun/scientifique, photo de l'utilisateur + photo de référence, description, habitat + carte, comportement, anecdotes, statut UICN coloré, sources/licences).
- Écran collection : grille par catégorie, silhouettes pour les espèces non capturées des Dex, recherche.

### Phase 4 — Gamification (1–2 semaines)
- Seed du catalogue de badges (volume, paliers par catégorie, 3–5 Dex régionaux curatés).
- Évaluation dans la transaction + écran badges avec progression + animation de déblocage.
- Notifications push (badge débloqué, rappel « 3 espèces de plus pour Ornithologue argent »).

### Phase 5 — Durcissement et bêta (2 semaines)
- Anti-triche minimal : hash perceptuel (même image resoumise ou partagée entre comptes), EXIF absent pour les imports galerie → capture marquée « importée », limite de débit.
- Hors-ligne : collection et fiches en cache SQLite ; file d'upload différée.
- Observabilité (Sentry, logs des prédictions pour améliorer les seuils), RGPD (suppression de compte, floutage de la position exacte des espèces sensibles).
- Bêta fermée TestFlight / Play Console (50–200 testeurs), mesure du taux d'identification correcte signalé par les utilisateurs.

**Total indicatif : 12–14 semaines** pour un·e développeur·se full-stack expérimenté·e, ~8 semaines à deux.

### Hors MVP (v2+)
Profils publics, amis et classements ; défis saisonniers ; carte communautaire des observations ; mode « expert » avec validation communautaire ; entraînement d'un modèle affiné sur les photos validées de l'app ; contribution des observations à GBIF/iNaturalist (avec consentement) ; contenu multilingue ; sons (chants d'oiseaux).

---

## 5. Risques et points d'attention

| Risque | Mitigation |
|---|---|
| Précision IA insuffisante sur insectes/araignées (espèces très proches) | Remontée au genre, choix parmi le top-3, badges adaptés (paliers plutôt que complétion) ; Phase 0 bloquante. |
| Triche (photos trouvées sur Internet) | Hash perceptuel, EXIF, distinction « capturé » vs « importé », éventuellement recherche d'image inversée sur les captures rares. |
| Animaux captifs (zoo, aquarium, parc animalier) | **Refus systématique** : la position de la photo est comparée aux contours des zoos et aquariums d'OpenStreetMap, une photo sans position est refusée, et la base bloque toute capture non vérifiée (`services/captivity/`). |
| Licences des données | Wikipedia CC BY-SA → attribution sur chaque fiche ; UICN → accord nécessaire pour un usage commercial ; photos de référence uniquement sous licence libre. |
| Espèces sensibles (braconnage) | Ne jamais exposer la localisation précise des espèces menacées ; flouter à 10 km. |
| Hallucinations du LLM dans les fiches | Génération contrainte aux sources fournies, citations, relecture humaine des fiches des espèces les plus capturées (`generation = 'reviewed'`). |
| Coût GPU | Redimensionnement côté client, cache par hash d'image, instances serverless avec scale-to-zero. |
