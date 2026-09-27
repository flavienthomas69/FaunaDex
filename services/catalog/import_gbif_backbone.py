#!/usr/bin/env python3
"""Extrait tout le règne animal du GBIF Backbone Taxonomy vers des CSV prêts à charger.

Source : https://hosted-datasets.gbif.org/datasets/backbone/current/backbone.zip
(archive Darwin Core, ~1 Go compressée). Le script lit l'archive en flux, sans la
décompresser sur disque, et produit dans --out :

  taxa.csv          un taxon accepté par ligne (embranchement → espèce), règne Animalia
  common_names.csv  noms vernaculaires fr / en des taxons retenus
  stats.json        nombre d'espèces par catégorie de jeu

Usage :
  python3 import_gbif_backbone.py --download --out build/
  python3 import_gbif_backbone.py --zip backbone.zip --out build/
  psql "$DATABASE_URL" -v build_dir=build -f load.sql

Uniquement la bibliothèque standard de Python (3.9+).
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import sys
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

BACKBONE_URL = "https://hosted-datasets.gbif.org/datasets/backbone/current/backbone.zip"

KEPT_RANKS = ("phylum", "class", "order", "family", "genus", "species")
LOCALES = {"fr": "fr", "fra": "fr", "fre": "fr", "en": "en", "eng": "en"}

# Catégories de jeu (cf. docs/CONCEPTION.md §2.1). Les « Poissons » et « Reptiles »
# ne sont pas des groupes taxonomiques : on les reconstruit à partir de plusieurs classes.
CLASS_TO_CATEGORY = {
    "Mammalia": "mammals",
    "Aves": "birds",
    "Reptilia": "reptiles", "Squamata": "reptiles", "Testudines": "reptiles",
    "Crocodylia": "reptiles", "Rhynchocephalia": "reptiles",
    "Amphibia": "amphibians",
    "Actinopterygii": "fish", "Sarcopterygii": "fish", "Elasmobranchii": "fish",
    "Holocephali": "fish", "Chondrichthyes": "fish", "Myxini": "fish",
    "Petromyzonti": "fish", "Cephalaspidomorphi": "fish", "Coelacanthi": "fish",
    "Dipneusti": "fish",
    "Insecta": "insects",
    "Arachnida": "arachnids",
    "Malacostraca": "crustaceans", "Maxillopoda": "crustaceans", "Branchiopoda": "crustaceans",
    "Ostracoda": "crustaceans", "Copepoda": "crustaceans", "Thecostraca": "crustaceans",
    "Hexanauplia": "crustaceans", "Remipedia": "crustaceans", "Cephalocarida": "crustaceans",
    "Ichthyostraca": "crustaceans",
}
PHYLUM_TO_CATEGORY = {"Mollusca": "molluscs"}
DEFAULT_CATEGORY = "other_invertebrates"


def category_for(phylum: str, klass: str) -> str:
    if klass in CLASS_TO_CATEGORY:
        return CLASS_TO_CATEGORY[klass]
    if phylum in PHYLUM_TO_CATEGORY:
        return PHYLUM_TO_CATEGORY[phylum]
    return DEFAULT_CATEGORY


def open_member(archive: zipfile.ZipFile, name: str) -> io.TextIOWrapper:
    """Ouvre un fichier de l'archive, où qu'il soit rangé (certaines versions ont un sous-dossier)."""
    member = next((m for m in archive.namelist() if m.rsplit("/", 1)[-1] == name), None)
    if member is None:
        sys.exit(f"{name} introuvable dans l'archive")
    return io.TextIOWrapper(archive.open(member), encoding="utf-8", newline="")


def tsv_rows(stream: io.TextIOWrapper):
    csv.field_size_limit(sys.maxsize)
    return csv.DictReader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)


def extract(archive: zipfile.ZipFile, out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    kept: set[str] = set()
    per_category: Counter[str] = Counter()

    with open_member(archive, "Taxon.tsv") as src, open(out / "taxa.csv", "w", newline="", encoding="utf-8") as dst:
        writer = csv.writer(dst)
        writer.writerow(["gbif_key", "parent_key", "rank", "scientific_name", "canonical_name",
                         "phylum", "class", "order", "family", "genus", "category"])
        for row in tsv_rows(src):
            if row.get("kingdom") != "Animalia":
                continue
            if (row.get("taxonomicStatus") or "").lower() != "accepted":
                continue
            rank = (row.get("taxonRank") or "").lower()
            if rank not in KEPT_RANKS:
                continue
            category = category_for(row.get("phylum", ""), row.get("class", ""))
            if rank == "phylum" and row.get("phylum") not in PHYLUM_TO_CATEGORY:
                category = ""  # un embranchement comme Chordata couvre plusieurs catégories
            writer.writerow([
                row["taxonID"], row.get("parentNameUsageID", ""), rank,
                row.get("scientificName", ""), row.get("canonicalName", ""),
                row.get("phylum", ""), row.get("class", ""), row.get("order", ""),
                row.get("family", ""), row.get("genus", ""), category,
            ])
            kept.add(row["taxonID"])
            if rank == "species":
                per_category[category] += 1

    names = 0
    seen: set[tuple[str, str, str]] = set()
    with open_member(archive, "VernacularName.tsv") as src, open(out / "common_names.csv", "w", newline="", encoding="utf-8") as dst:
        writer = csv.writer(dst)
        writer.writerow(["gbif_key", "locale", "name"])
        for row in tsv_rows(src):
            locale = LOCALES.get((row.get("language") or "").lower())
            name = (row.get("vernacularName") or "").strip()
            if not locale or not name or row["taxonID"] not in kept:
                continue
            key = (row["taxonID"], locale, name.lower())
            if key in seen:
                continue
            seen.add(key)
            writer.writerow([row["taxonID"], locale, name])
            names += 1

    stats = {
        "source": BACKBONE_URL,
        "species_total": sum(per_category.values()),
        "species_by_category": dict(per_category.most_common()),
        "taxa_rows": len(kept),
        "common_names": names,
    }
    (out / "stats.json").write_text(json.dumps(stats, indent=2, ensure_ascii=False), encoding="utf-8")
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--zip", type=Path, help="archive backbone.zip déjà téléchargée")
    src.add_argument("--download", action="store_true", help="télécharger l'archive depuis GBIF")
    parser.add_argument("--out", type=Path, default=Path("build"))
    args = parser.parse_args()

    path = args.zip
    if args.download:
        path = args.out / "backbone.zip"
        args.out.mkdir(parents=True, exist_ok=True)
        print(f"Téléchargement de {BACKBONE_URL} …", file=sys.stderr)
        urllib.request.urlretrieve(BACKBONE_URL, path)

    with zipfile.ZipFile(path) as archive:
        stats = extract(archive, args.out)
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
