#!/usr/bin/env bash
# find_ingredient.sh
# Usage: ./find_ingredient.sh -i "<ingredient>" -d /path/to/folder
# Output: product_name<TAB>code per match, then: Found N product(s) containing: "<INGREDIENT>"

set -euo pipefail
export CSVKIT_FIELD_SIZE_LIMIT=$((1024 * 1024 * 1024))

INGREDIENT=""
DATA_DIR=""

usage() {
  echo "Usage: $0 -i \"<ingredient>\" -d /path/to/folder"
  echo "  -i   ingredient to search (case-insensitive)"
  echo "  -d   folder containing products.csv (tab-separated)"
  echo "  -h   show help"
}

while getopts ":i:d:h" opt; do
  case "$opt" in
    i) INGREDIENT="$OPTARG" ;;
    d) DATA_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[ -z "${INGREDIENT:-}" ] && { echo "ERROR: -i <ingredient> is required" >&2; usage; exit 1; }
[ -z "${DATA_DIR:-}" ] && { echo "ERROR: -d /path/to/folder is required" >&2; usage; exit 1; }

CSV="$DATA_DIR/products.csv"

# Graceful: missing/empty file → 0 results
if [ ! -s "$CSV" ]; then
  echo "ERROR: $CSV not found or empty." >&2
  echo "----"
  echo "Found 0 product(s) containing: \"${INGREDIENT}\""
  exit 0
fi

# Require csvkit tools (csvkit <1.0.5 recommended)
for cmd in csvcut csvgrep csvformat; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found. Please install csvkit (<1.0.5)." >&2; exit 1; }
done

# Check required columns exist from header (normalize CR)
header="$(head -n1 "$CSV" | tr -d '\r' || true)"
missing=""
for col in ingredients_text product_name code; do
  case "$header" in *"$col"*) : ;; *) missing="$missing $col" ;; esac
done
if [ -n "$missing" ]; then
  echo "WARNING: Missing required column(s):$missing" >&2
  echo "----"
  echo "Found 0 product(s) containing: \"${INGREDIENT}\""
  exit 0
fi

# Core pipeline (TSV throughout); add placeholders for missing name/code
tmp_matches="$(mktemp)"
set +e
tr
