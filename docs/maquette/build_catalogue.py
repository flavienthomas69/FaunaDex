#!/usr/bin/env python3
"""Génère catalogue.json pour la maquette à partir du paquet npm species-names-dataset.

    npm pack species-names-dataset@0.0.13 && tar xzf species-names-dataset-0.0.13.tgz
    python3 docs/maquette/build_catalogue.py package/data > docs/maquette/catalogue.json

Données : Wikispecies via species-names-dataset, licence CC BY-SA 4.0.
Le paquet ne couvre que les oiseaux, les mammifères et les reptiles ; la vraie app
importe tout le règne animal depuis GBIF (services/catalog/).
"""
import json
import re
import sys
from pathlib import Path

CLASSES = {"Aves": "ois", "Mammalia": "mam", "Reptilia": "rep"}
TAG = re.compile(r"<[^>]*>")


def clean(name: str) -> str:
    return TAG.sub("", name).split(",")[0].strip()


def main(data_dir: Path) -> None:
    out = {}
    for folder, cat in CLASSES.items():
        lines = {}
        for f in sorted((data_dir / "Vertebrata" / folder).glob("*.json")):
            for sp in json.loads(f.read_text(encoding="utf-8")):
                sci = " ".join(sp["scientific_name"].split())
                if len(sci.split()) != 2:
                    continue
                names = {c["lang"]: clean(c["name"]) for c in sp["common_names"]}
                if names.get("fr"):
                    lines[sci] = f"{sci}|{names['fr']}|f"
                elif names.get("en"):
                    lines[sci] = f"{sci}|{names['en']}|e"
                else:
                    lines[sci] = sci
        out[cat] = "\n".join(lines[k] for k in sorted(lines))
    json.dump({
        "source": "Wikispecies via species-names-dataset 0.0.13",
        "license": "CC BY-SA 4.0",
        "species": out,
    }, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
