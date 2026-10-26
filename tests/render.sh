#!/usr/bin/env bash
# Reference renders: frame a few synthetic test photos in every style and option, with fixed random
# textures (BORDERMAGICK_SEED), so a change can be checked against a saved baseline pixel for pixel.
#
#   tests/render.sh baseline [photo …]   render into tests/out/baseline/
#   tests/render.sh compare  [photo …]   render into tests/out/current/ and compare with the baseline
#
# Without photo arguments it uses generated test photos (tests/out/photos/). Extra real photos can be
# passed to test them too; they are copied, never changed.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
BM="$HERE/../bordermagick"
OUT="${RENDER_OUT:-$HERE/out}"   # RENDER_OUT keeps several baselines apart
export BORDERMAGICK_SEED=42

mode=${1:-}; shift || true
[[ "$mode" == baseline || "$mode" == compare ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# --- Test photos (shared with tests/unit.sh)
. "$HERE/photos.sh"

# --- The matrix: "name|options"
CASES=(
  "white|"            "white-nopaper|-p 0"   "black|-b black"       "cream|-b cream"
  "auto|-b auto"      "hex|-b #2B4C7E"       "sunset|-b sunset"     "gradient|-b #FFD6E0-#B5E2FA"
  "dusk|-b dusk"      "frost|-b frost"       "frost-dark|-b frost-dark"
  "marble|-b marble"  "marble-dark|-b marble-dark" "marble-green|-b marble-green"
  "marble-beige|-b marble-beige" "terrazzo|-b terrazzo" "linen|-b linen" "contact|-b contact"
  "museum|-b museum"  "museum-white|-b museum-white" "museum-black|-b museum-black"
  "poster|-b poster"  "poster-colour|-b poster-colour" "postcard|-b postcard"
  "cover-yellow|-b cover-yellow" "cover-red|-b cover-red"
  "fit|-s fit"        "fhd|-s fhd -b marble" "px500|-s 500 -b contact" "strip|-m strip -b sunset"
)

render() {  # dir photo…
  local dir=$1; shift
  mkdir -p "$dir"; rm -f "$dir"/*.png
  local work="$OUT/work"; rm -rf "$work"; mkdir -p "$work"
  local p c name opts base f
  for p in "$@"; do
    base=$(basename "${p%.*}")
    cp "$p" "$work/$base.jpg"
    for c in "${CASES[@]}"; do
      name=${c%%|*}; opts=${c#*|}
      rm -f "$work/${base}"_*_*.jpg
      # shellcheck disable=SC2086
      "$BM" $opts "$work/$base.jpg" >/dev/null 2>"$work/err.txt" || { echo "FAILED: $base $name"; cat "$work/err.txt"; continue; }
      f=$(ls "$work/${base}"_*_*.jpg)
      # Pixels plus the metadata the frame carries, so both are compared
      magick "$f" "$dir/${base}__${name}.png"
      exiftool -s -s -s -Make -Model -Title -GPSPosition "$f" > "$dir/${base}__${name}.meta" || true
      printf "."
    done
  done
  echo
}

make_photos "$OUT/photos"
if (( $# )); then photos=( "$@" ); else photos=( "$OUT"/photos/*.jpg ); fi

if [[ "$mode" == baseline ]]; then
  render "$OUT/baseline" "${photos[@]}"
  echo "Baseline: $(ls "$OUT/baseline"/*.png | wc -l | tr -d ' ') renders in $OUT/baseline"
  exit 0
fi

render "$OUT/current" "${photos[@]}"
fail=0
for b in "$OUT"/baseline/*.png; do
  n=$(basename "$b"); c="$OUT/current/$n"
  if [[ ! -f "$c" ]]; then echo "MISSING  $n"; fail=1; continue; fi
  if ! cmp -s "${b%.png}.meta" "${c%.png}.meta"; then echo "METADATA $n"; fail=1; fi
  if [[ "$(magick identify -format %wx%h "$b")" != "$(magick identify -format %wx%h "$c")" ]]; then
    echo "SIZE     $n  $(magick identify -format %wx%h "$b") -> $(magick identify -format %wx%h "$c")"; fail=1; continue
  fi
  ae=$(magick compare -metric AE "$b" "$c" null: 2>&1 | awk '{print $1}') || true
  [[ "$ae" == 0 ]] || { echo "DIFFERS  $n  ($ae pixels)"; magick compare "$b" "$c" "$OUT/current/${n%.png}.diff.png" 2>/dev/null || true; fail=1; }
done
(( fail )) && { echo "Some renders changed (diff images in $OUT/current/)."; exit 1; }
echo "All $(ls "$OUT/baseline"/*.png | wc -l | tr -d ' ') renders identical to the baseline."
