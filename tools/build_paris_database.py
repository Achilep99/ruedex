#!/usr/bin/env python3
"""Construit l'asset compact RueDex à partir des exports Paris Data.

Le script privilégie les tronçons axiaux. Si un code voie n'est pas raccordé au
jeu des tronçons, il garde la géométrie surfacique de la nomenclature officielle.
Aucune biographie n'est inventée : seul le champ officiel d'origine du nom est
conservé, lorsqu'il est présent.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import unicodedata
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ROAD_TYPES = {
    "RUE", "AVENUE", "BOULEVARD", "PLACE", "IMPASSE", "CHEMIN", "ROUTE",
    "QUAI", "ALLEE", "PASSAGE", "SQUARE", "CITE", "VILLA", "COUR",
    "PROMENADE", "SENTIER", "TERRASSE", "PORT", "PONT", "CARREFOUR",
}
CONNECTORS = {"DE", "DU", "DES", "LA", "LE", "LES", "D", "L", "AU", "AUX", "A", "ET"}


def normalized_key(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]", "", value.lower())


def normalize_text(value: Any) -> str:
    text = "" if value is None else str(value)
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^A-Za-z0-9 '\-/]", " ", text).upper()
    return re.sub(r"\s+", " ", text).strip()


def normalize_code(value: Any) -> str:
    if isinstance(value, bool) or value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    text = normalize_text(value)
    return text[:-2] if text.endswith(" 0") and text[:-2].isdigit() else text


def significant_name(value: str) -> str:
    tokens = re.split(r"[\s'\-/]+", normalize_text(value))
    return " ".join(
        token for token in tokens
        if token and token not in ROAD_TYPES and token not in CONNECTORS
    )


def as_records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [flatten_record(item) for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        if payload.get("type") == "FeatureCollection":
            return [flatten_record(item) for item in payload.get("features", [])]
        for key in ("results", "records", "features"):
            if isinstance(payload.get(key), list):
                return [flatten_record(item) for item in payload[key] if isinstance(item, dict)]
    raise ValueError("Format JSON d'export non reconnu")


def flatten_record(record: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for nested_key in ("fields", "properties"):
        nested = record.get(nested_key)
        if isinstance(nested, dict):
            result.update(nested)
    result.update({k: v for k, v in record.items() if k not in {"fields", "properties"}})
    if "geometry" in record and "__feature_geometry" not in result:
        result["__feature_geometry"] = record["geometry"]
    return result


def field(record: dict[str, Any], candidates: Iterable[str], default: Any = "") -> Any:
    index = {normalized_key(str(key)): key for key in record}
    for candidate in candidates:
        key = index.get(normalized_key(candidate))
        if key is not None:
            value = record.get(key)
            if value not in (None, ""):
                return value
    return default


def find_geometry(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        if isinstance(value.get("type"), str) and "coordinates" in value:
            return value
        if isinstance(value.get("geometry"), dict):
            found = find_geometry(value["geometry"])
            if found:
                return found
        for candidate in ("geo_shape", "geoshape", "shape", "geom", "the_geom", "__feature_geometry"):
            if candidate in value:
                found = find_geometry(value[candidate])
                if found:
                    return found
    return None


def geometry_paths(geometry: dict[str, Any] | None) -> list[list[list[float]]]:
    if not geometry:
        return []
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if not isinstance(coordinates, list):
        return []
    if kind == "LineString":
        return [coordinates]
    if kind == "MultiLineString":
        return coordinates
    if kind == "Polygon":
        return coordinates
    if kind == "MultiPolygon":
        return [ring for polygon in coordinates for ring in polygon]
    if kind == "GeometryCollection":
        result: list[list[list[float]]] = []
        for child in geometry.get("geometries", []):
            result.extend(geometry_paths(child))
        return result
    return []


def point_line_distance(point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]) -> float:
    px, py = point
    ax, ay = start
    bx, by = end
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def simplify(points: list[list[float]], tolerance: float = 0.000012) -> list[list[float]]:
    clean: list[list[float]] = []
    for raw in points:
        if not isinstance(raw, list) or len(raw) < 2:
            continue
        lon, lat = float(raw[0]), float(raw[1])
        if not (-180 <= lon <= 180 and -90 <= lat <= 90):
            continue
        pair = [lon, lat]
        if not clean or pair != clean[-1]:
            clean.append(pair)
    if len(clean) <= 2:
        return clean

    def recurse(start: int, end: int, selected: set[int]) -> None:
        maximum = 0.0
        index = -1
        a = tuple(clean[start])
        b = tuple(clean[end])
        for i in range(start + 1, end):
            distance = point_line_distance(tuple(clean[i]), a, b)
            if distance > maximum:
                maximum, index = distance, i
        if index >= 0 and maximum > tolerance:
            selected.add(index)
            recurse(start, index, selected)
            recurse(index, end, selected)

    selected = {0, len(clean) - 1}
    recurse(0, len(clean) - 1, selected)
    result = [clean[i] for i in sorted(selected)]
    if len(result) > 220:
        step = (len(result) - 1) / 219
        result = [result[round(i * step)] for i in range(220)]
    return result


def convert_paths(paths: list[list[list[float]]]) -> list[list[list[float]]]:
    converted: list[list[list[float]]] = []
    for path in paths:
        simplified = simplify(path)
        if len(simplified) >= 2:
            # L'asset Flutter utilise [latitude, longitude].
            converted.append([[round(lat, 6), round(lon, 6)] for lon, lat in simplified])
    return converted


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--denominations", required=True, type=Path)
    parser.add_argument("--segments", required=True, type=Path)
    parser.add_argument("--rarity-overrides", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--minimum-streets", type=int, default=3000)
    args = parser.parse_args()

    denominations = as_records(load_json(args.denominations))
    segments = as_records(load_json(args.segments))

    overrides: dict[str, str] = {}
    if args.rarity_overrides and args.rarity_overrides.exists():
        raw_overrides = load_json(args.rarity_overrides)
        overrides = {normalized_key(key): str(value) for key, value in raw_overrides.items()}

    segments_by_code: dict[str, list[list[list[float]]]] = defaultdict(list)
    segments_by_name: dict[str, list[list[list[float]]]] = defaultdict(list)
    for record in segments:
        geometry = find_geometry(record)
        paths = geometry_paths(geometry)
        if not paths:
            continue
        code = normalize_code(field(record, ["cvoie", "code voie vdp", "code voie ville de paris", "code voie", "code_voie", "voie_id", "identifiant"]))
        name = normalize_text(field(record, ["lvoie", "libelle voie", "nom voie", "denomination", "voie", "libelle", "nom"])).strip()
        if code:
            segments_by_code[code].extend(paths)
        if name:
            segments_by_name[significant_name(name)].extend(paths)

    streets_by_id: dict[str, dict[str, Any]] = {}
    min_lat, max_lat = math.inf, -math.inf
    min_lon, max_lon = math.inf, -math.inf

    for index, record in enumerate(denominations):
        official = str(field(record, ["typo", "typo_min", "denomination complete", "denomination", "lvoie", "libelle voie", "nom complet", "nom"])).strip()
        if not official:
            continue
        normalized_official = normalize_text(official)
        sig_name = significant_name(official)
        if not sig_name:
            continue

        code = normalize_code(field(record, ["cvoie", "code voie vdp", "code voie ville de paris", "code voie", "code_voie", "identifiant", "id"]))
        raw_id = code or f"PARIS_{index}_{sig_name}"
        street_id = re.sub(r"[^A-Z0-9]+", "_", raw_id).strip("_").lower()

        paths = segments_by_code.get(code, []) if code else []
        if not paths:
            paths = segments_by_name.get(sig_name, [])
        if not paths:
            paths = geometry_paths(find_geometry(record))
        converted = convert_paths(paths)
        if not converted:
            continue

        for segment in converted:
            for lat, lon in segment:
                min_lat, max_lat = min(min_lat, lat), max(max_lat, lat)
                min_lon, max_lon = min(min_lon, lon), max(max_lon, lon)

        road_type = normalize_text(field(record, ["typvoie", "type voie", "nature voie"]))
        if not road_type:
            first_token = normalized_official.split(" ", 1)[0]
            road_type = first_token if first_token in ROAD_TYPES else ""

        origin = str(field(record, ["orig", "origine du nom", "origine_nom", "origine"])).strip()
        arrondissement = str(field(record, ["arrdt", "arrondissement", "ardt"])).strip()
        rarity_lookup_key = normalized_key(official)
        rarity = overrides.get(rarity_lookup_key, "nonClassee")

        existing = streets_by_id.get(street_id)
        if existing is None:
            streets_by_id[street_id] = {
                "id": street_id,
                "officialName": official,
                "roadType": road_type,
                "normalizedName": sig_name,
                "aliases": [],
                "city": "Paris",
                "arrondissement": arrondissement,
                "origin": origin,
                "rarity": rarity,
                "raritySource": "override" if rarity_lookup_key in overrides else "non_classee",
                "segments": converted,
            }
        else:
            # Certaines emprises peuvent être découpées en plusieurs objets.
            # Elles doivent rester une seule entrée RueDex portant tous leurs
            # tronçons, pas plusieurs cartes identiques dans la collection.
            known = {
                tuple(tuple(point) for point in segment)
                for segment in existing["segments"]
            }
            for segment in converted:
                signature = tuple(tuple(point) for point in segment)
                if signature not in known:
                    existing["segments"].append(segment)
                    known.add(signature)
            if not existing["origin"] and origin:
                existing["origin"] = origin
            if not existing["arrondissement"] and arrondissement:
                existing["arrondissement"] = arrondissement

    streets = list(streets_by_id.values())
    if len(streets) < args.minimum_streets:
        raise SystemExit(
            f"Seulement {len(streets)} voies générées ; minimum attendu : {args.minimum_streets}. "
            "Vérifie les champs et les exports Paris Data."
        )

    streets.sort(key=lambda item: normalize_text(item["officialName"]))
    output = {
        "metadata": {
            "sourceLabel": "Ville de Paris — Paris Data — ODbL",
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "streetCount": len(streets),
            "bounds": {
                "minLatitude": round(min_lat - 0.002, 6),
                "maxLatitude": round(max_lat + 0.002, 6),
                "minLongitude": round(min_lon - 0.003, 6),
                "maxLongitude": round(max_lon + 0.003, 6),
            },
        },
        "streets": streets,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(output, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"RueDex : {len(streets)} voies écrites dans {args.output}")


if __name__ == "__main__":
    main()
