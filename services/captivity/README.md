# Refus des animaux en captivité

Une photo d'animal prise dans un zoo, un aquarium, un parc animalier, un safari-parc ou une mini-ferme **ne donne jamais de capture**. Le contrôle repose sur la position de la photo, comparée aux contours de ces lieux dans OpenStreetMap.

## Règles

| Situation | Verdict | Résultat pour le joueur |
|---|---|---|
| Le cercle d'incertitude GPS touche un site captif (contour + 50 m, ou 300 m autour d'un site connu par un simple point) | `captive` | Photo refusée, le nom du lieu est affiché |
| Pas de position (localisation coupée, photo de galerie sans GPS) | `no_location` | Photo refusée, invitation à activer la localisation |
| Précision GPS moins bonne que 100 m | `imprecise` | Photo refusée, invitation à réessayer à découvert |
| Aucun site captif à proximité | `ok` | Identification et capture normales |

Les photos de galerie utilisent la position EXIF. Sans précision indiquée dans l'EXIF, on retient 50 m.

Le contrôle porte sur le **contour du zoo**, pas sur tout le parc qui l'entoure : une mésange photographiée dans le parc de la Tête d'Or, loin des enclos, reste valable.

Les captures de squelettes du Paléo-Dex (docs/CONCEPTION.md §2.5) suivent la règle inverse : elles doivent être prises dans un musée.

## Défense en profondeur

1. **API** : appelle `captivity_check(lon, lat, precision)` avant l'identification et enregistre le verdict dans `observations.captivity_verdict`. Une photo refusée n'est pas envoyée au modèle de vision, ce qui économise aussi le calcul GPU.
2. **Base de données** : le déclencheur `captures_require_wild` refuse toute capture d'animal vivant dont l'observation n'a pas le verdict `ok`, même si l'API a un bug.
3. **Application** : la position vient du GPS du téléphone au moment de la prise de vue, pas de l'EXIF, et les positions simulées sont rejetées (`isMock` sur Android, signaux de jailbreak sur iOS).

## Mise en place

```bash
# Schéma (après celui de docs/CONCEPTION.md, PostGIS requis)
psql "$DATABASE_URL" -f services/captivity/schema.sql

# Sites captifs depuis OpenStreetMap, pays par pays (Overpass)
python3 services/captivity/import_osm_captive_sites.py --country FR --country BE --out build/captive_sites.csv
psql "$DATABASE_URL" -v csv=build/captive_sites.csv -f services/captivity/load.sql

# Tests
python3 -m unittest discover -s services/captivity/tests
psql "$TEST_DATABASE_URL" -v csv=<sites de test>.csv -f services/captivity/tests/test_check.sql
```

Tags OpenStreetMap importés : `tourism=zoo` (et son sous-type `zoo=*` : `petting_zoo`, `safari_park`, `wildlife_park`, `falconry`…), `tourism=aquarium`, `attraction=animal`.

## Limites connues

- OpenStreetMap n'est pas exhaustif : un petit parc animalier ou une animalerie peuvent manquer. Les joueurs peuvent signaler un lieu, ajouté ensuite à la main (`source = 'manual'`).
- Pour un site décrit par une relation OSM, on retient son rectangle englobant : c'est plus large que le site réel, donc plus strict.
- Un animal échappé ou un oiseau sauvage posé dans un zoo sera refusé : c'est le prix d'une règle simple.
- Un second contrôle par l'image (barreaux, vitres, grillage, étiquette d'enclos), fait par le modèle de vision, est prévu pour les zoos absents de la carte.
