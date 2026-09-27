// Génère carte.json pour la maquette : fonds de carte pré-projetés et positions des lieux.
// La page n'a ainsi besoin d'aucune bibliothèque de cartographie.
//
//   npm i d3-geo@3 topojson-client@3 world-atlas@2
//   node docs/maquette/build_map.mjs > docs/maquette/carte.json
//
// Fond de carte : Natural Earth via world-atlas (domaine public).
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

function view(projection, width, height, landTopo, borders) {
  const path = geoPath(projection).digits(1);
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
  };
}

const W = 350;
const franceBox = { type: "MultiPoint", coordinates: [[-5.2, 42.2], [9.6, 51.3]] };
const france = geoConicConformal().rotate([-3, 0]).parallels([44, 49]).fitExtent([[6, 6], [W - 6, 334]], franceBox);
const world = geoNaturalEarth1().fitExtent([[4, 4], [W - 4, 186]], { type: "Sphere" });

process.stdout.write(JSON.stringify({
  source: "Natural Earth via world-atlas 2.0.2 (domaine public)",
  france: view(france.clipExtent([[0, 0], [W, 340]]), W, 340, land50,
    mesh(countries50, countries50.objects.countries, (a, b) => a !== b)),
  world: view(world, W, 190, land110, null),
}));
