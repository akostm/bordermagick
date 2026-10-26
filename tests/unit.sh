#!/usr/bin/env bash
# Unit checks for lib/: the template engine, layout files (parsing, extends, errors) and the tags read
# from the generated test photos. Quick; no renders.
#
#   tests/unit.sh
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="${RENDER_OUT:-$HERE/out}"
FIX="$HERE/layouts"

SEP="∙"
die() { echo "$1" >&2; exit 1; }   # lib errors end the subshell a check runs in
. "$ROOT/lib/tags.sh"
. "$ROOT/lib/layout.sh"
. "$ROOT/lib/engine.sh"
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

# --- Layout files
LY_VAR_border="#FFFFFF"; LY_VAR_paper=6
LAYOUT_PATH="$FIX/builtin"
layout_load grand
check "dump grand (extends child, base)" "$(cat "$FIX/grand.expected")" "$(layout_dump)"
check "items after remove" "title exposure where" "$LY_ITEMS"
check "layout_get" "{place} ∙ {date}" "$(layout_get i_where content)"
check "source of a value" "$FIX/builtin/child.layout:6" "$LYS_frame__background"
check "quoted value keeps spaces" "  kept with its spaces  " "$(LAYOUT_PATH="$FIX/builtin"; layout_load base; layout_get layout description)"
check "variables" "#FFFFFF|paper 6" "$(layout_load base; echo "$(layout_get frame background)|$(layout_get frame texture)")"
check "unset variable kept" '$border' "$(LY_VAR_border=""; layout_load base; layout_get frame background)"

LAYOUT_PATH="$FIX/user:$FIX/builtin"
check "user layout wins" "$FIX/user/base.layout" "$(layout_find base)"
check "list" "base mine child grand" "$(layout_list)"
check "user layout extends built-in" "title exposure where line|Mine" "$(layout_load mine; echo "$LY_ITEMS|$(layout_get layout category)")"

LAYOUT_PATH="$FIX/errors:$FIX/builtin"
E="$FIX/errors"
fails_with "loop"           "loop: loop-a → loop-b → loop-a"                    layout_load loop-a
fails_with "unknown key"    "$E/bad-key.layout:5: unknown key 'colour' in [text title]" layout_load bad-key
fails_with "bad line"       "$E/bad-line.layout:3: expected [section] or key = value" layout_load bad-line
fails_with "name mismatch"  "name = other, but the file is name-mismatch.layout" layout_load name-mismatch
fails_with "type clash"     "$E/type-clash.layout:4: [rule title] is a text item" layout_load type-clash
fails_with "unknown var"    "$E/unknown-var.layout:2: unknown variable \$colour" layout_load unknown-var
fails_with "planned type"   "[swatches] items are planned"                      layout_load planned
fails_with "unnamed item"   "$E/unnamed.layout:3: [text] needs a name"           layout_load unnamed
fails_with "no section"     "$E/no-section.layout:2: 'padding' comes before any [section]" layout_load no-section
fails_with "missing parent" "no layout 'nothing-here'"                         layout_load no-parent
fails_with "open quote"     "$E/open-quote.layout:2: missing closing \""        layout_load open-quote
fails_with "bad type"       "$E/bad-type.layout:1: unknown item type 'texts'"   layout_load bad-type
fails_with "no such layout" "no layout 'nope'"                                 layout_load nope
fails_with "self extend"    "extends self-loop, but there is no other self-loop.layout" layout_load self-loop

# --- Engine: units, shorthand, fonts, tracks
S=1000; W=1500; H=1000; FW=1600; PX_EM=40; PX_REF=""; BM_HOME="$HERE/out/nohome"
u() { echo $(( S * $1 / 1000 )); }
pxv() { PX_REF=${2:-} px "$1"; echo "$REPLY"; }
check "px pmin = u()"     "$(u 26)"  "$(pxv 2.6pmin)"
check "px rounding"       "$(( 1234 * 17 / 1000 ))" "$(S=1234 pxv 1.7pmin)"
check "px pw, ph, fw"     "150 50 16" "$(pxv 10pw) $(pxv 5ph) $(pxv 1fw)"
check "px em, px, 0"      "20 7 0"   "$(pxv 0.5em) $(pxv 7px) $(pxv 0)"
check "px %"              "250"      "$(pxv 25% 1000)"
check "px negative"       "-10"      "$(pxv -1pmin)"
fails_with "px no unit"   "needs a unit"         px 3
fails_with "px bad unit"  "unknown unit 'pt'"    px 3pt
fails_with "px % here"    "% can't be used here" px 5%
fails_with "px fw unknown" "fw can't be used"    eval 'FW=0 px 1fw'
check "box4 1" "a a a a" "$(box4 a; echo "$REPLY")"
check "box4 2" "a b a b" "$(box4 'a b'; echo "$REPLY")"
check "box4 3" "a b c b" "$(box4 'a b c'; echo "$REPLY")"
check "box4 4" "a b c d" "$(box4 'a b c d'; echo "$REPLY")"
check "split at top-level commas" "0 1px rgba(0,0,0,0.5)|2px 0 0 red" "$(split_top '0 1px rgba(0,0,0,0.5), 2px 0 0 red'; IFS='|'; echo "${SPLIT[*]}")"
check "font registered"  "HelveticaNeue-Bold" "$(font_file HelveticaNeue-Bold normal normal; echo "$REPLY")"
check "font regular"     "/System/Library/Fonts/Supplemental/Georgia.ttf" "$(font_file Georgia normal normal; echo "$REPLY")"
check "font bold"        "/System/Library/Fonts/Supplemental/Georgia Bold.ttf" "$(font_file Georgia bold normal; echo "$REPLY")"
check "font italic"      "/System/Library/Fonts/Supplemental/Georgia Italic.ttf" "$(font_file Georgia normal italic; echo "$REPLY")"
check "font one weight"  "/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf" "$(font_file 'DIN Alternate' normal normal; echo "$REPLY")"
check "font unknown"     "1" "$(font_file 'No Such Font' normal normal; echo $?)"
tracks() { solve_tracks "$@"; echo "$REPLY"; }
check "tracks fr"          "300 600"         "$(tracks '1fr 2fr' 900 0 '')"
check "tracks auto fr"     "120 780"         "$(tracks 'auto 1fr' 900 0 '120 0')"
check "tracks gap"         "440 440"         "$(tracks '1fr 1fr' 900 20 '')"
check "tracks %"           "252 396 252"     "$(tracks '28% 44% 28%' 900 0 '')"
check "tracks fixed fr"    "100 800"         "$(tracks '10pmin 1fr' 900 0 '')"
check "tracks decimal fr"  "300 600"         "$(tracks '0.5fr 1fr' 900 0 '')"
check "tracks unknown size" "50 30"          "$(tracks 'auto 1fr' -1 0 '50 30')"
check "tracks overfull"    "1000 0"          "$(tracks '100pmin 1fr' 900 0 '')"
fails_with "tracks % unknown" "% needs a known size" solve_tracks '50%' -1 0 ''

# --- Engine: errors in layout files, through the script
B="$HERE/engine/bad"
bad() { ( cd "$OUT/photos" && BORDERMAGICK_LAYOUTS="$B" "$ROOT/bordermagick" --plan -b "$1" fuji_33.jpg ); }
fails_with "engine bad unit"    "$B/bad-unit.layout:2: '3pt': unknown unit 'pt'"       bad bad-unit
fails_with "engine bad font"    "$B/bad-font.layout:3: no font 'No Such Font'"         bad bad-font
fails_with "engine background"  "background film is not available yet"                bad bad-bg
fails_with "engine material"    "unknown material 'granite'"                          bad bad-material
fails_with "engine frost"       "frost(light) or frost(dark)"                         bad bad-frost
fails_with "engine effect"      "effect is none, inset or drop-shadow"                bad bad-effect
fails_with "engine text effect" "text-effect is none or engrave"                      bad bad-text-effect
fails_with "engine later item"  "[edge-print] items are not available yet"             bad later-item
fails_with "engine anchor"      "'middle' is not a photo anchor"                      bad bad-anchor
fails_with "engine fw side"     "fw can't be used here"                               bad fw-side
fails_with "engine no room"     "[bottom] has no room"                                bad no-room
fails_with "engine no column"   "[bottom] has only 1 column(s)"                       bad no-column
fails_with "engine colour"      "$B/bad-colour.layout:2: unknown colour 'notacolour'"  bad bad-colour

# --- Engine: plans of the test layouts on the test photos
make_photos "$OUT/photos"
for f in "$HERE"/engine/*.layout; do
  l=${f##*/}; l=${l%.layout}
  check "plan $l" "$(cat "$HERE/engine/$l.plan" 2>/dev/null)" \
    "$(cd "$OUT/photos" && BORDERMAGICK_LAYOUTS="$HERE/engine" "$ROOT/bordermagick" --plan -b "$l" fuji_33.jpg no_exif.jpg sony_portrait.jpg 2>&1)"
done

# --- Tags of the generated test photos, through the script
make_photos "$OUT/photos"
check "tags of the test photos" "$(cat "$HERE/tags.expected")" \
  "$(cd "$OUT/photos" && "$ROOT/bordermagick" --tags fuji_33.jpg no_exif.jpg sony_portrait.jpg)"

# --- Text from metadata reaches ImageMagick as it is: no @file reads, no backslash or % escapes
eval "$(grep '^im_text()' "$ROOT/bordermagick")"
esc() { check "im_text $1" "$2" "$(im_text "$1")"; }
esc 'Erechtheion' 'Erechtheion'
esc '@f.txt'      '\@f.txt'
esc 'a@b'         'a@b'
esc 'a\b'         'a\\b'
esc '\@x'         '\\@x'
esc '100% %w'     '100%% %%w'
# A photo titled "@file" (and with "@file" as its city) frames the same whether that file exists or not,
# in every way text is drawn: -annotate (white), label: (museum, postcard), caption: (poster)
at="$OUT/at"; rm -rf "$at"; mkdir -p "$at/with" "$at/without"
cp "$OUT/photos/fuji_33.jpg" "$at/at.jpg"
exiftool -q -overwrite_original "-XMP:Title=@$at/secret.txt" "-XMP:City=@$at/secret.txt" \
  -DateTimeOriginal= -CreateDate= -ModifyDate= "$at/at.jpg"   # (no date: the poster's place column is just "@file")
for b in white museum poster postcard; do
  echo "LEAKED FILE CONTENTS" > "$at/secret.txt"
  cp "$at/at.jpg" "$at/with/at.jpg"; cp "$at/at.jpg" "$at/without/at.jpg"
  BORDERMAGICK_SEED=42 "$ROOT/bordermagick" -b $b "$at/with/at.jpg" >/dev/null 2>&1
  rm "$at/secret.txt"
  BORDERMAGICK_SEED=42 "$ROOT/bordermagick" -b $b "$at/without/at.jpg" >/dev/null 2>&1
  ae=$(magick compare -metric AE "$at"/with/at_*_*.jpg "$at"/without/at_*_*.jpg null: 2>&1 | awk '{print $1}')
  check "@file title, -b $b" 0 "$ae"
  rm -f "$at"/with/at_*_*.jpg "$at"/without/at_*_*.jpg
done

echo "$pass passed, $fail failed"
(( fail == 0 ))
