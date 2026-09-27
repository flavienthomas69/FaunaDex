#!/usr/bin/env python3
"""Importe depuis OpenStreetMap les lieux où des animaux sont détenus.

Tags retenus : tourism=zoo (avec son sous-type zoo=*), tourism=aquarium, zoo=*,
attraction=animal (enclos). La requête Overpass est faite pays par pays.

  python3 import_osm_captive_sites.py --country FR --country BE --out build/captive_sites.csv
  python3 import_osm_captive_sites.py --overpass-json fr.json --out build/captive_sites.csv
  psql "$DATABASE_URL" -v csv=build/captive_sites.csv -f load.sql

Uniquement la bibliothèque standard de Python (3.9+).
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
QUERY = """[out:json][timeout:900];
area["ISO3166-1"="{country}"][admin_level=2]->.a;
(
  nwr(area.a)["tourism"="zoo"];
  nwr(area.a)["tourism"="aquarium"];
  nwr(area.a)["zoo"];
  nwr(area.a)["attraction"="animal"];
);
out geom;"""

POLYGON_BUFFER_M = 50   # marge autour d'un contour connu
POINT_BUFFER_M = 300    # rayon retenu quand OSM ne donne qu'un point


def kind_of(tags: dict) -> str:
    if tags.get("tourism") == "aquarium":
        return "aquarium"
    if tags.get("zoo"):
        return tags["zoo"]
    if tags.get("attraction") == "animal":
        return "enclosure"
    return "zoo"


def ring_wkt(points: list[dict]) -> str:
    coords = [(p["lon"], p["lat"]) for p in points]
    if coords[0] != coords[-1]:
        coords.append(coords[0])
    return "(" + ", ".join(f"{lon} {lat}" for lon, lat in coords) + ")"


def bbox_wkt(b: dict) -> str:
    w, s, e, n = b["minlon"], b["minlat"], b["maxlon"], b["maxlat"]
    return f"POLYGON(({w} {s}, {e} {s}, {e} {n}, {w} {n}, {w} {s}))"


def to_row(el: dict) -> list | None:
    """Convertit un élément Overpass (sortie `out geom`) en ligne CSV, ou None s'il est inexploitable."""
    tags = el.get("tags", {})
    name = tags.get("name:fr") or tags.get("name") or ""
    if el["type"] == "node":
        wkt, buffer_m = f"POINT({el['lon']} {el['lat']})", POINT_BUFFER_M
    elif el["type"] == "way" and len(el.get("geometry", [])) >= 3:
        wkt, buffer_m = f"POLYGON({ring_wkt(el['geometry'])})", POLYGON_BUFFER_M
    elif el["type"] == "relation" and "bounds" in el:
        # Assembler les anneaux d'un multipolygone demande une vraie bibliothèque SIG ;
        # le rectangle englobant est plus large que le site, donc plus strict, ce qui convient ici.
        wkt, buffer_m = bbox_wkt(el["bounds"]), POLYGON_BUFFER_M
    else:
        return None
    return [el["type"], el["id"], name, kind_of(tags), wkt, buffer_m]


def fetch(country: str) -> dict:
    data = urllib.parse.urlencode({"data": QUERY.format(country=country)}).encode()
    req = urllib.request.Request(OVERPASS_URL, data=data, headers={"User-Agent": "FaunaDex/0.1"})
    with urllib.request.urlopen(req, timeout=1000) as res:
        return json.load(res)


def write_csv(elements: list[dict], out: Path) -> int:
    out.parent.mkdir(parents=True, exist_ok=True)
    seen, count = set(), 0
    with open(out, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["osm_type", "osm_id", "name", "kind", "wkt", "buffer_m"])
        for el in elements:
            key = (el["type"], el["id"])
            row = None if key in seen else to_row(el)
            if row:
                seen.add(key)
                writer.writerow(row)
                count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--country", action="append", help="code ISO 3166-1 alpha-2, répétable")
    src.add_argument("--overpass-json", type=Path, action="append", help="réponse Overpass déjà téléchargée")
    parser.add_argument("--out", type=Path, default=Path("build/captive_sites.csv"))
    args = parser.parse_args()

    elements: list[dict] = []
    for country in args.country or []:
        print(f"Overpass : {country}…", file=sys.stderr)
        elements += fetch(country)["elements"]
    for path in args.overpass_json or []:
        elements += json.loads(path.read_text(encoding="utf-8"))["elements"]
    print(f"{write_csv(elements, args.out)} sites écrits dans {args.out}")


if __name__ == "__main__":
    main()
