#!/usr/bin/env bash
# Unit checks for lib/: the template engine and the tags read from the generated test photos.
# Quick; no renders.
#
#   tests/unit.sh
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="${RENDER_OUT:-$HERE/out}"

SEP="∙"
die() { echo "$1" >&2; exit 1; }   # lib errors end the subshell a check runs in
. "$ROOT/lib/tags.sh"
. "$HERE/photos.sh"

pass=0; fail=0
check() {  # name expected actual
  if [[ "$2" == "$3" ]]; then pass=$(( pass + 1 ))
  else fail=$(( fail + 1 )); printf 'FAIL %s\n  expected: %q\n  got:      %q\n' "$1" "$2" "$3"; fi
}
fails_with() {  # name expected-message-part command…
  local name=$1 want=$2 err; shift 2
  err=$( ( "$@" ) 2>&1 >/dev/null ) && { fail=$(( fail + 1 )); echo "FAIL $name: no error"; return; }
  if [[ "$err" == *"$want"* ]]; then pass=$(( pass + 1 ))
  else fail=$(( fail + 1 )); printf 'FAIL %s\n  expected an error with: %s\n  got: %s\n' "$name" "$want" "$err"; fi
}

# --- Templates, on a fixed set of tags
for t in $TAG_NAMES; do printf -v "T_$t" '%s' ""; done
T_city=Athens; T_country=Greece; T_date="5 October 2023"; X_DateTimeOriginal="2023:10:05 11:12:30"
T_focal="35.8 mm"; T_aperture="ƒ/11.0"; T_iso="ISO 200"; T_model=X-T20; T_brand=Fujifilm
T_filename=fuji_33; T_frame=33
tpl() { expand "$2"; check "template $1: $2" "$3" "$REPLY"; }
tpl tag        '{city}'                                   'Athens'
tpl fallback   '{title|city|filename}'                    'Athens'
tpl fallback2  '{title|filename}'                         'fuji_33'
tpl seps       '{focal} ∙ {aperture} ∙ {shutter} ∙ {iso}' '35.8 mm ∙ ƒ/11.0 ∙ ISO 200'
tpl sep-first  '{shutter} ∙ {focal}'                      '35.8 mm'
tpl sep-last   '{focal} ∙ {shutter}'                      '35.8 mm'
tpl all-empty  '{title} ∙ {shutter}'                      ''
tpl leading    'No. {frame}'                              'No. 33'
tpl trailing   '({shutter})'                              '()'
tpl group-gone 'Digital photograph[, {brand} {film}]'     'Digital photograph'
tpl group      'Digital photograph[, {brand} {model}]'    'Digital photograph, Fujifilm X-T20'
tpl groups     '[Shot on {model}][ with {film}]'          'Shot on X-T20'
tpl group-sep  '{city}[ ∙ {title}] ∙ {country}'           'Athens ∙ Greece'
tpl nested     '[{model}[ ({film})]]'                     'X-T20'
tpl nested2    '[{model}[ ({brand})]]'                    'X-T20 (Fujifilm)'
tpl year       '{date:%Y}'                                '2023'
tpl stamp      "{date:'%y %m %d}"                         "'23 10 05"
tpl newline    '{city}\n{country}'                        $'Athens\nGreece'
tpl escapes    '\{city\} \[x\] a\\b'                      '{city} [x] a\b'
tpl plain      'Digital photograph'                       'Digital photograph'
fails_with "template unknown tag"  "unknown tag {nope}"          expand '{nope}'
fails_with "template open {"       "'{' without '}'"             expand '{city'
fails_with "template open ["       "'[' without ']'"             expand '[{city}'
fails_with "template stray ]"      "']' without '['"             expand '{city}]'
fails_with "template stray }"      "'}' without '{'"             expand 'city}'
fails_with "template format"       ":format only works on {date}" expand '{city:%Y}'

# --- Tags of the generated test photos, through the script
make_photos "$OUT/photos"
check "tags of the test photos" "$(cat "$HERE/tags.expected")" \
  "$(cd "$OUT/photos" && "$ROOT/bordermagick" --tags fuji_33.jpg no_exif.jpg sony_portrait.jpg)"

echo "$pass passed, $fail failed"
(( fail == 0 ))
