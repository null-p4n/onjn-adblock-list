#!/usr/bin/env bash
# update.sh - refresh the ONJN blocklist files from the official source.
#
# Usage:  ./update.sh
# Env:    OUTDIR=<dir>        output directory (default: directory of this script)
#         SRC_FILE=<path>     use a local copy of Lista-neagra.txt instead of downloading
#         ONJN_URL=<url>      override the source URL
#         ALLOW_HTTP=1        retry over plain http if https fails (injectable in transit)
#         MIN_ENTRIES=500     abort if fewer valid domains than this are parsed
#         MAX_SHRINK_PCT=50   abort if the list shrinks by more than this percentage
#         FORCE=1             bypass the safety checks above
#         DRY_RUN=1           show what would change, write nothing
#
# Writes onjn_domains.txt (plain) and onjn_adguard.txt (||domain^). Existing files are only
# replaced when the content changed and the new list passes the sanity checks.

set -euo pipefail
export LC_ALL=C

URL="${ONJN_URL:-https://onjn.gov.ro/wp-content/uploads/Onjn.gov.ro/Acasa/BlackList/Lista-neagra.txt}"
OUTDIR="${OUTDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SRC_FILE="${SRC_FILE:-}"
ALLOW_HTTP="${ALLOW_HTTP:-0}"
MIN_ENTRIES="${MIN_ENTRIES:-500}"
MAX_SHRINK_PCT="${MAX_SHRINK_PCT:-50}"
FORCE="${FORCE:-0}"
DRY_RUN="${DRY_RUN:-0}"

die() { echo "error: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RAW="$TMP/raw.txt"
DOM="$OUTDIR/onjn_domains.txt"
ADG="$OUTDIR/onjn_adguard.txt"

# ---- fetch ----
if [[ -n $SRC_FILE ]]; then
  [[ -f $SRC_FILE ]] || die "SRC_FILE not found: $SRC_FILE"
  cp "$SRC_FILE" "$RAW"
else
  command -v curl >/dev/null || die "curl not found"
  fetch() {
    curl -fsSL --connect-timeout 10 --max-time 60 \
      -A 'Mozilla/5.0 (compatible; onjn-list-updater)' -o "$RAW" "$1"
  }
  if ! fetch "$URL"; then
    if [[ $ALLOW_HTTP == 1 && $URL == https://* ]]; then
      echo "warn: https download failed, retrying over http" >&2
      fetch "http://${URL#https://}" || die "download failed: $URL"
    else
      die "download failed: $URL (set ALLOW_HTTP=1 to retry over plain http)"
    fi
  fi
fi
[[ -s $RAW ]] || die "source is empty"

# ---- normalize: strip BOM/CR, lowercase, drop scheme/path/port/leading www ----
sed $'1s/^\xEF\xBB\xBF//' "$RAW" | tr -d '\r' | tr 'A-Z' 'a-z' |
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s|^[a-z]+://||; s|[/?#].*$||; s/:[0-9]+$//; s/^www\.//' |
  grep -v '^$' > "$TMP/cand.txt" || true

VALID='^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$'
NEW="$TMP/new.txt"
grep -E "$VALID" "$TMP/cand.txt" | sort -u > "$NEW" || true
rejected=$(grep -vcE "$VALID" "$TMP/cand.txt" || true)
new_n=$(wc -l < "$NEW" | tr -d ' ')

# ---- sanity checks ----
if [[ $FORCE != 1 && $new_n -lt $MIN_ENTRIES ]]; then
  die "only $new_n valid domains parsed (MIN_ENTRIES=$MIN_ENTRIES); keeping existing files"
fi
OLD="$TMP/old.txt"; : > "$OLD"
if [[ -f $DOM ]]; then sort -u "$DOM" | grep -v '^$' > "$OLD" || true; fi
old_n=$(wc -l < "$OLD" | tr -d ' ')
if [[ $FORCE != 1 && $old_n -gt 0 ]]; then
  floor=$(( old_n * (100 - MAX_SHRINK_PCT) / 100 ))
  (( new_n >= floor )) || die "list shrank from $old_n to $new_n (more than ${MAX_SHRINK_PCT}%); rerun with FORCE=1 if intended"
fi

# ---- diff ----
comm -13 "$OLD" "$NEW" > "$TMP/added.txt"
comm -23 "$OLD" "$NEW" > "$TMP/removed.txt"
added=$(wc -l < "$TMP/added.txt" | tr -d ' ')
removed=$(wc -l < "$TMP/removed.txt" | tr -d ' ')
if (( added == 0 && removed == 0 )); then
  echo "no changes ($new_n entries)"
  exit 0
fi
echo "entries: $old_n -> $new_n (+$added / -$removed; $rejected unparseable lines skipped)"
if (( added > 0 )); then echo "added:";   head -n 10 "$TMP/added.txt"   | sed 's/^/  + /'; (( added > 10 )) && echo "  ... and $((added-10)) more"; fi
if (( removed > 0 )); then echo "removed:"; head -n 10 "$TMP/removed.txt" | sed 's/^/  - /'; (( removed > 10 )) && echo "  ... and $((removed-10)) more"; fi
[[ $DRY_RUN == 1 ]] && { echo "dry run: nothing written"; exit 0; }

# ---- write (temp file + rename, so a failure never leaves a half-written list) ----
mkdir -p "$OUTDIR"
cp "$NEW" "$DOM.tmp"
{
  printf '! Title: ONJN Romania unlicensed gambling domains\n'
  printf '! Source: %s\n' "$URL"
  printf '! Updated: %s\n' "$(date -u +%F)"
  printf '! Entries: %s\n' "$new_n"
  printf '! Note: ||domain^ also blocks all subdomains\n'
  sed 's/.*/||&^/' "$NEW"
} > "$ADG.tmp"
mv "$DOM.tmp" "$DOM"
mv "$ADG.tmp" "$ADG"
echo "wrote $DOM and $ADG"
