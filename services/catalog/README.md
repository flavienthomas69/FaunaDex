# Catalogue des espèces

Import de **tout le règne animal** depuis le [GBIF Backbone Taxonomy](https://www.gbif.org/dataset/d7dddbf4-2cf0-4f39-9b2a-bb099caae36c) vers le schéma décrit dans `docs/CONCEPTION.md` §2.2.

```bash
# 1. Extraire le règne Animalia (télécharge ~1 Go, lecture en flux)
python3 services/catalog/import_gbif_backbone.py --download --out build/

# 2. Charger dans PostgreSQL (idempotent, relançable à chaque version du Backbone)
psql "$DATABASE_URL" -v build_dir=build -f services/catalog/load.sql

# Tests
python3 -m unittest discover -s services/catalog/tests
```

Ce qui est importé :

| Fichier | Contenu |
|---|---|
| `taxa.csv` | Tous les taxons **acceptés** d'Animalia, de l'embranchement à l'espèce, avec leur parent et leur catégorie de jeu |
| `common_names.csv` | Noms vernaculaires français et anglais |
| `stats.json` | Nombre d'espèces par catégorie |

Les catégories de jeu (Mammifères, Oiseaux, Reptiles, Amphibiens, Poissons, Insectes, Arachnides, Crustacés, Mollusques, Autres invertébrés) sont reconstruites à partir des classes GBIF : « Reptiles » regroupe par exemple Squamata, Testudines et Crocodylia.

À faire ensuite :
- Écarter les taxons fossiles (le Backbone contient aussi des espèces éteintes connues uniquement par des fossiles).
- Compléter les noms français via Wikidata, beaucoup plus fourni que GBIF sur ce point.
- Le texte des fiches est généré séparément (voir §1.5 de la conception), à la première capture ou à l'avance pour les espèces courantes.

Licence : le GBIF Backbone est publié sous CC BY 4.0. Citer GBIF dans l'application.
