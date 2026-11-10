#!/usr/bin/env bash
# Downloads the third-party CC0 source packs used by the art bake into
# Tools/bake/sources/<pack>/ (git-ignored: raw sources are never committed).
# Each pack is unzipped into its own folder. Nothing in them is executed.
#
#   Tools/bake/fetch-sources.sh            # all packs
#   Tools/bake/fetch-sources.sh nature-kit # one pack
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/sources"
mkdir -p "$SRC"
JAR="$(mktemp)"
UA="Mozilla/5.0 (EvolutionDefense asset bake)"

KENNEY_PACKS=(tower-defense-kit castle-kit nature-kit space-kit blaster-kit mini-characters graveyard-kit pirate-kit
              particle-pack ui-pack-adventure interface-sounds impact-sounds sci-fi-sounds rpg-audio)
PACKS=("${@:-${KENNEY_PACKS[@]}}")

for slug in "${PACKS[@]}"; do
    dest="$SRC/kenney-$slug"
    if [[ -d "$dest" ]]; then echo "✓ $slug (already downloaded)"; continue; fi
    page="$(curl -fsSL -c "$JAR" -b "$JAR" -A "$UA" "https://kenney.nl/assets/$slug")"
    id="$(grep -o "data-download-id='[0-9a-f]*'" <<<"$page" | head -1 | cut -d"'" -f2)"
    [[ -n "$id" ]] || { echo "✗ $slug: no download id"; continue; }
    url="$(curl -fsSL -c "$JAR" -b "$JAR" -A "$UA" -H "Referer: https://kenney.nl/assets/$slug" \
           "https://kenney.nl/download-link/$id" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
    tmp="$(mktemp -d)"
    curl -fsSL -c "$JAR" -b "$JAR" -A "$UA" -o "$tmp/pack.zip" "$url"
    mkdir -p "$dest"
    unzip -q "$tmp/pack.zip" -d "$dest"
    shasum -a 256 "$tmp/pack.zip" | cut -d' ' -f1 > "$dest/.download-sha256"
    echo "https://kenney.nl/assets/$slug" > "$dest/.source-url"
    date -u +%Y-%m-%d > "$dest/.downloaded"
    rm -rf "$tmp"
    echo "✓ $slug ($(du -sh "$dest" | cut -f1))"
done
rm -f "$JAR"

# OpenGameArt mirrors (all CC0) of the creature packs the enemy bake uses.
# Skipped when specific Kenney packs were named on the command line.
[[ $# -gt 0 ]] && exit 0
OGA=(
  "oga-quaternius-animated-mech-pack|animated_mech_pack_-_march_2021.zip|https://opengameart.org/content/animated-mech-pack|CC0"
  "oga-quaternius-animated-monster-pack|Animated%20Monster%20Pack%20by%20%40Quaternius.zip|https://opengameart.org/content/lowpoly-animated-monsters|CC0"
  "oga-quaternius-animated-robot|Animated%20Robot%20-%20Oct%202018.zip|https://opengameart.org/content/animated-lowpoly-robot|CC0"
  "oga-quaternius-cute-monsters|cute_animated_monsters_-_aug_2020.zip|https://opengameart.org/content/textured-cute-monster-pack|CC0"
  "oga-boar|boar_0.blend|https://opengameart.org/content/boar|CC0 (Teh_Bucket)"
)
for entry in "${OGA[@]}"; do
    IFS='|' read -r name file page lic <<<"$entry"
    dest="$SRC/$name"
    if [[ -d "$dest" ]]; then echo "✓ $name (already downloaded)"; continue; fi
    mkdir -p "$dest"
    tmp="$(mktemp -d)"
    curl -fsSL -A "$UA" -o "$tmp/$file" "https://opengameart.org/sites/default/files/$file"
    case "$file" in *.zip) unzip -q "$tmp/$file" -d "$dest" ;; *) cp "$tmp/$file" "$dest/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "$file")" ;; esac
    echo "$page" > "$dest/.source-url"; echo "$lic" > "$dest/.license"; date -u +%Y-%m-%d > "$dest/.downloaded"
    rm -rf "$tmp"
    echo "✓ $name"
done

# KayKit character packs (CC0, the author's own GitHub): heroes, militia and the Desert skeletons.
for r in Adventures Skeletons; do
    name="kaykit-$(tr '[:upper:]' '[:lower:]' <<<"$r")"
    dest="$SRC/$name"
    if [[ -d "$dest" ]]; then echo "✓ $name (already downloaded)"; continue; fi
    url="https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-$r-1.0"
    git clone -q --depth 1 "$url" "$dest" && rm -rf "$dest/.git"
    echo "$url" > "$dest/.source-url"; echo "CC0 1.0 (pack README)" > "$dest/.license"; date -u +%Y-%m-%d > "$dest/.downloaded"
    echo "✓ $name"
done

# Manual downloads (no stable direct link):
#  • Quaternius "Ultimate Monsters" (CC0): https://quaternius.com/packs/ultimatemonsters.html
#    → the "Big" set's glTF folder goes to sources/quaternius-ultimatemonsters/Ultimate Monsters/Big/glTF/.
#  • Quaternius "Animal Pack vol. 2" (CC0): https://opengameart.org/content/animated-animales-low-poly
#    → unzip into sources/oga-quaternius-animal-pack-vol2/.
#  • Quaternius "Ultimate Animated Animals" (CC0): https://quaternius.com/packs/ultimateanimatedanimals.html
#    → unzip into sources/quaternius-ultimateanimatedanimals/ (keeps "Ultimate Animated Animals - July 2021/glTF").
#  • Lilita One (SIL OFL 1.1): https://fonts.google.com/specimen/Lilita+One
#    → already copied to EvolutionDefense/AssetPack/Fonts/ with its OFL text.
[[ -d "$SRC/quaternius-ultimateanimatedanimals" ]] || echo "! download Ultimate Animated Animals manually (see the end of this script)"
