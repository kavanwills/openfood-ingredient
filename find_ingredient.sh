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

# Detect delimiter from the header (tab → use -t, else assume comma)
header="$(head -n1 "$CSV" | tr -d '\r' || true)"
CSV_DOPT=""
case "$header" in
  *$'\t'*) CSV_DOPT="-t" ;;   # TSV
  *) CSV_DOPT="" ;;           # CSV (default)
esac

# Check required columns exist (string check is fine for both CSV/TSV)
missing=0
for col in ingredients_text product_name code; do
  case "$header" in *"$col"*) : ;; *) missing=1 ;; esac
done
if [ $missing -eq 1 ]; then
  echo "WARNING: Missing required column(s)." >&2
  echo "----"
  echo "Found 0 product(s) containing: \"${INGREDIENT}\""
  exit 0
fi

# Core pipeline: parse with detected delimiter; always output TSV; add placeholders
tmp_matches="$(mktemp)"
set +e
tr -d '\r' < "$CSV" \
| csvcut   $CSV_DOPT -c ingredients_text,product_name,code \
| csvgrep  $CSV_DOPT -c ingredients_text -r "(?i)${INGREDIENT}" \
| csvcut   $CSV_DOPT -c product_name,code \
| csvformat -T \
| tail -n +2 \
| while IFS=$'\t' read -r name code; do
    [ -z "$name" ] && name="<missing_name>"
    [ -z "$code" ] && code="<missing_code>"
    printf "%s\t%s\n" "$name" "$code"
  done \
| tee "$tmp_matches"
status=$?
set -e

if [ $status -ne 0 ]; then
  echo "ERROR: Filtering pipeline failed." >&2
  rm -f "$tmp_matches"
  exit $status
fi

count="$(wc -l < "$tmp_matches" | tr -d '[:space:]')"
echo "----"
echo "Found ${count} product(s) containing: \"${INGREDIENT}\""

rm -f "$tmp_matches"
