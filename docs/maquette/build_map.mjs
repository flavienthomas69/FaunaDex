// Génère carte.json pour la maquette : fonds de carte pré-projetés et positions des lieux.
// La page n'a ainsi besoin d'aucune bibliothèque de cartographie.
//
//   npm i d3-geo@3 topojson-client@3 world-atlas@2
//   # Natural Earth 10m (fleuves, lacs, massifs, villes) depuis github.com/nvkelso/natural-earth-vector/geojson
//   NE_DIR=chemin/vers/geojson node docs/maquette/build_map.mjs > docs/maquette/carte.json
//
// Fond de carte : Natural Earth via world-atlas et natural-earth-vector (domaine public).
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { geoConicConformal, geoNaturalEarth1, geoPath, geoGraticule10 } from "d3-geo";
import { feature, mesh } from "topojson-client";

const require = createRequire(process.cwd() + "/");
const land50 = require("world-atlas/land-50m.json");
const countries50 = require("world-atlas/countries-50m.json");
const land110 = require("world-atlas/land-110m.json");

// Lieux utilisés par la démo : [longitude, latitude]
export const PLACES = {
  "Parc de la Tête d'Or, Lyon": [4.855, 45.777],
  "Forêt de Fontainebleau": [2.70, 48.40],
  "Parc de Parilly, Bron": [4.90, 45.72],
  "Jardin, Villeurbanne": [4.88, 45.77],
  "Monts du Lyonnais": [4.45, 45.65],
  "Mont d'Or": [4.80, 45.83],
  "Croix-Rousse, Lyon": [4.83, 45.775],
  "Étangs de la Dombes": [5.03, 46.0],
  "Plage du Sillon, Saint-Malo": [-2.02, 48.655],
  "Beaujolais": [4.60, 46.08],
  "Mare du jardin, Villeurbanne": [4.88, 45.77],
  "Infusion de foin": [4.88, 45.77],
  "Lac du Der-Chantecoq": [4.76, 48.56],
  "Parc national des Écrins": [6.30, 44.85],
  "Camargue, Saintes-Maries-de-la-Mer": [4.43, 43.45],
  "Zoo du parc de la Tête d'Or, Lyon": [4.853, 45.772],
  "Aquarium de Lyon, La Mulatière": [4.81, 45.73],
  "mus:mnhn": [2.357, 48.842],
  "mus:irsnb": [4.376, 50.837],
  "mus:esperaza": [2.21, 42.93],
  "mus:berlin": [13.38, 52.53],
  "mus:nhm": [-0.176, 51.496],
  "mus:naturalis": [4.47, 52.165],
  "mus:senckenberg": [8.652, 50.117],
  "mus:frick": [8.02, 47.51],
  "mus:field": [-87.617, 41.866],
  "mus:nmnh": [-77.026, 38.891],
  "mus:carnegie": [-79.949, 40.443],
  "mus:mor": [-111.05, 45.66],
  "mus:mongolie": [106.917, 47.918],
  "mus:yale": [-72.925, 41.315],
  "mus:rom": [-79.395, 43.668],
  "mus:amnh": [-73.974, 40.781],
  "mus:trelew": [-65.30, -43.25],
  "mus:macn": [-58.44, -34.605],
};

// Hotspots de démonstration : centres de mailles de 0,5°, jamais la position d'une observation.
export const HOTSPOTS = [
  { cell: [4.75, 45.75], family: "Rapaces nocturnes", observers: 14 },
  { cell: [5.25, 46.25], family: "Hérons et aigrettes", observers: 23 },
  { cell: [4.25, 45.75], family: "Amphibiens", observers: 9 },
  { cell: [5.75, 45.25], family: "Libellules", observers: 11 },
  { cell: [4.75, 46.25], family: "Papillons de jour", observers: 17 },
  { cell: [4.75, 48.75], family: "Grues cendrées", observers: 41 },
  { cell: [4.25, 43.75], family: "Flamants et limicoles", observers: 36 },
];

const NE = name => JSON.parse(readFileSync(`${process.env.NE_DIR}/${name}.geojson`, "utf8"));
const rivers = [...NE("ne_10m_rivers_lake_centerlines").features, ...NE("ne_10m_rivers_europe").features];
const lakes = NE("ne_10m_lakes").features;
const regions = NE("ne_10m_geography_regions_polys").features;
const cities = NE("ne_10m_populated_places_simple").features;

// Couches de détail, visibles uniquement dans les zones découvertes
function details(path, projection, { riverMax, lakeMax, rangeMax, cityMin, worldCities }) {
  const cls = r => r <= 5 ? 0 : r <= 8 ? 1 : r <= 9 ? 2 : 3;
  const riverPaths = [[], [], [], []];
  for (const f of rivers) {
    const r = f.properties.scalerank; if (r > riverMax) continue;
    const d = path(f); if (d) riverPaths[cls(r)].push(d);
  }
  const lakePath = lakes.filter(f => f.properties.scalerank <= lakeMax).map(f => path(f)).filter(Boolean).join("");
  const ranges = regions
    .filter(f => ["Range/mtn", "Plateau"].includes(f.properties.FEATURECLA) && f.properties.SCALERANK <= rangeMax && !/péninsule/i.test(f.properties.NAME_FR))
    .map(f => ({ d: path(f), name: f.properties.NAME_FR, xy: path.centroid(f).map(v => Math.round(v)) }))
    .filter(r => r.d && r.d.length > 20);
  const towns = cities
    .filter(f => worldCities ? f.properties.worldcity === 1 || f.properties.megacity === 1 : f.properties.pop_max >= cityMin)
    .map(f => ({ xy: projection([f.properties.longitude, f.properties.latitude]), name: f.properties.name, pop: f.properties.pop_max }))
    .filter(c => c.xy && c.xy[0] >= 0 && c.xy[1] >= 0 && c.xy[0] <= 350 && c.xy[1] <= 340)
    .map(c => [Math.round(c.xy[0] * 10) / 10, Math.round(c.xy[1] * 10) / 10, c.name, c.pop])
    .sort((a, b) => b[3] - a[3]);
  return { rivers: riverPaths.map(a => a.join("")), lakes: lakePath, ranges, towns };
}

// Supprime les sommets à moins de `tol` pixels du précédent : allège les tracés sans changer l'aspect.
function thinned(projection, tol) {
  return {
    stream(out) {
      let last = null;
      return projection.stream({
        point(x, y) { if (last && Math.hypot(x - last[0], y - last[1]) < tol) return; last = [x, y]; out.point(x, y); },
        lineStart() { last = null; out.lineStart(); }, lineEnd() { out.lineEnd(); },
        polygonStart() { out.polygonStart(); }, polygonEnd() { out.polygonEnd(); },
        sphere() { out.sphere && out.sphere(); },
      });
    },
  };
}

function view(projection, width, height, landTopo, borders, detailOpts) {
  const path = geoPath(detailOpts.tol ? thinned(projection, detailOpts.tol) : projection).digits(1);
  const project = ([lon, lat]) => projection([lon, lat]).map(v => Math.round(v * 10) / 10);
  // Échelle locale : pixels pour 10 km, mesurée à Lyon
  const [x0] = projection([4.85, 45.75]);
  const [x1] = projection([4.85 + 10 / (111.32 * Math.cos(45.75 * Math.PI / 180)), 45.75]);
  return {
    width, height,
    land: path(feature(landTopo, landTopo.objects.land)),
    borders: borders ? path(borders) : "",
    graticule: path(geoGraticule10()),
    px10km: Math.round((x1 - x0) * 100) / 100,
    places: Object.fromEntries(Object.entries(PLACES).map(([k, v]) => [k, project(v)])),
    hotspots: HOTSPOTS.map(h => ({ ...h, xy: project(h.cell) })),
    ...details(path, projection, detailOpts),
  };
}

const W = 350;
const franceBox = { type: "MultiPoint", coordinates: [[-5.2, 42.2], [9.6, 51.3]] };
const france = geoConicConformal().rotate([-3, 0]).parallels([44, 49]).fitExtent([[6, 6], [W - 6, 334]], franceBox);
const world = geoNaturalEarth1().fitExtent([[4, 4], [W - 4, 186]], { type: "Sphere" });

process.stdout.write(JSON.stringify({
  source: "Natural Earth, via world-atlas 2.0.2 et natural-earth-vector (domaine public)",
  france: view(france.clipExtent([[0, 0], [W, 340]]), W, 340, land50,
    mesh(countries50, countries50.objects.countries, (a, b) => a !== b),
    { riverMax: 12, lakeMax: 12, rangeMax: 5, cityMin: 40000, tol: 0.12 }),
  world: view(world, W, 190, land110, null,
    { riverMax: 2, lakeMax: 0, rangeMax: 1, worldCities: true, tol: 0.35 }),
}));
