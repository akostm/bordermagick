# bordermagick — layout engine: turns a loaded layout (lib/layout.sh) into a frame. See docs/layouts.md.
# Sourced by bordermagick; only defines functions. Uses the script's helpers (prepare_logo, logo_height,
# auto_colour, canvas_ink, paper, upper, titlecase, im_text, die) and the tags (lib/tags.sh).
#
# Per photo: ly_resolve (units, text, grid -> a box per item), then ly_plan (print) or ly_draw (args for
# the one magick command that write_out runs). Item state lives in I_<item>__<field> variables.

LY_REGISTERED="HelveticaNeue-Bold HelveticaNeue-Medium Futura-CondExtraBold"
LY_ANCHORS="top-left top-center top-right left center right bottom-left bottom-center bottom-right"

lv()   { local v="LYV_${1//-/_}__${2//-/_}"; REPLY=${!v-}; }   # section key -> REPLY
lerr() {  # section key message: an error at the line the value came from
  local v="LYS_${1//-/_}__${2//-/_}"
  die "${!v:-layout}: $3"
}
ist() { printf -v "I_${1//-/_}__$2" '%s' "$3"; }               # item field value
igt() { local v="I_${1//-/_}__$2"; REPLY=${!v-}; }              # item field -> REPLY


# =====================================================================================================
# Units
# =====================================================================================================
# A length in pixels (REPLY), rounded towards zero. Context: S W H, FW (0 = not known yet), PX_EM (the
# item's font size), PX_REF (what % refers to; empty = not allowed). Errors point at section/key if given.
px() {  # value [section key]
  local v=$1 int frac milli unit r
  if ! [[ "$v" =~ ^(-?)([0-9]*)(\.([0-9]+))?([a-z%]*)$ ]] || [[ -z "${BASH_REMATCH[2]}${BASH_REMATCH[4]}" ]]; then
    px_err "'$v' is not a length" "${2:-}" "${3:-}"
  fi
  int=${BASH_REMATCH[2]:-0}; frac="${BASH_REMATCH[4]}000"; unit=${BASH_REMATCH[5]}
  milli=$(( 10#$int * 1000 + 10#${frac:0:3} ))
  case "$unit" in
    pmin) r=$(( S * milli / 100000 )) ;;
    pw)   r=$(( W * milli / 100000 )) ;;
    ph)   r=$(( H * milli / 100000 )) ;;
    fw)   (( ${FW:-0} > 0 )) || px_err "'$v': fw can't be used here (the frame width isn't known yet)" "${2:-}" "${3:-}"
          r=$(( FW * milli / 100000 )) ;;
    em)   r=$(( ${PX_EM:-0} * milli / 1000 )) ;;
    %)    [[ -n "${PX_REF:-}" ]] || px_err "'$v': % can't be used here" "${2:-}" "${3:-}"
          r=$(( PX_REF * milli / 100000 )) ;;
    px)   r=$(( milli / 1000 )) ;;
    "")   (( milli == 0 )) || px_err "'$v' needs a unit: pmin, pw, ph, fw, em, % or px" "${2:-}" "${3:-}"; r=0 ;;
    *)    px_err "'$v': unknown unit '$unit'" "${2:-}" "${3:-}" ;;
  esac
  [[ "$v" == -* ]] && r=$(( -r ))
  REPLY=$r
  return 0
}
px_err() { if [[ -n "${2:-}" ]]; then lerr "$2" "$3" "$1"; else die "$1"; fi; }

# CSS shorthand: 1–4 values -> REPLY "top right bottom left"
box4() {  # value [section key]
  local a=()
  read -r -a a <<<"$1"
  case ${#a[@]} in
    1) REPLY="${a[0]} ${a[0]} ${a[0]} ${a[0]}" ;;
    2) REPLY="${a[0]} ${a[1]} ${a[0]} ${a[1]}" ;;
    3) REPLY="${a[0]} ${a[1]} ${a[2]} ${a[1]}" ;;
    4) REPLY="${a[0]} ${a[1]} ${a[2]} ${a[3]}" ;;
    *) px_err "'$1' needs 1 to 4 values" "${2:-}" "${3:-}" ;;
  esac
  return 0
}

# Split at commas outside parentheses: "0 1px 2px rgba(0,0,0,.5), 1px 0 0 red" -> SPLIT=( … )
split_top() {
  local s=$1 c depth=0 cur="" i
  SPLIT=()
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      "(") depth=$(( depth + 1 )); cur+=$c ;;
      ")") depth=$(( depth - 1 )); cur+=$c ;;
      ,) if (( depth == 0 )); then SPLIT+=( "$(ly_trim "$cur")" ); cur=""; else cur+=$c; fi ;;
      *) cur+=$c ;;
    esac
  done
  [[ -n "$(ly_trim "$cur")" ]] && SPLIT+=( "$(ly_trim "$cur")" )
  return 0
}

# Track sizes. spec: "1fr auto 28% 4pmin"; inner: the space to share (-1 = unknown: fr acts as auto);
# autos: the content size of each track. -> REPLY "size size …"
solve_tracks() {  # spec inner gap autos [section key]
  local spec=($1) inner=$2 gap=$3 autos=($4) n i t used=0 frs=0 rem sizes=()
  n=${#spec[@]}
  for (( i = 0; i < n; i++ )); do
    t=${spec[i]}
    case "$t" in
      auto) sizes[i]=${autos[i]:-0} ;;
      *fr)  [[ "${t%fr}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || px_err "'$t' is not a track size" "${5:-}" "${6:-}"
            if (( inner < 0 )); then sizes[i]=${autos[i]:-0}; else sizes[i]=fr; fi ;;
      *)    if [[ "$t" == *% ]] && (( inner < 0 )); then px_err "'$t': % needs a known size" "${5:-}" "${6:-}"; fi
            PX_REF=$inner px "$t" "${5:-}" "${6:-}"; sizes[i]=$REPLY ;;
    esac
    [[ "${sizes[i]}" == fr ]] || used=$(( used + sizes[i] ))
  done
  # Share what's left between the fr tracks
  for (( i = 0; i < n; i++ )); do [[ "${sizes[i]}" == fr ]] && frs=$(( frs + $(fr_milli "${spec[i]}") )); done
  if (( frs > 0 )); then
    rem=$(( inner - used - gap * (n - 1) )); (( rem < 0 )) && rem=0
    for (( i = 0; i < n; i++ )); do
      [[ "${sizes[i]}" == fr ]] && sizes[i]=$(( rem * $(fr_milli "${spec[i]}") / frs ))
    done
  fi
  REPLY="${sizes[*]}"
  return 0
}
fr_milli() { local f=${1%fr} i d; i=${f%%.*}; d=""; [[ "$f" == *.* ]] && d=${f#*.}; d="${d}000"; echo $(( 10#${i:-0} * 1000 + 10#${d:0:3} )); }

# =====================================================================================================
# Fonts and text properties
# =====================================================================================================
# Font for ImageMagick (REPLY): a registered face, a file in ~/.bordermagick/fonts or the system's font
# folders ("<family>[ Bold][ Italic].ttf|otf"); a family with one weight falls back to it
font_file() {  # family weight style
  local fam=$1 w=$2 st=$3 d sfx ext tries=()
  fam=${fam#\"}; fam=${fam%\"}
  case " $LY_REGISTERED " in *" $fam "*) REPLY=$fam; return 0 ;; esac
  if [[ "$fam" == /* && -f "$fam" ]]; then REPLY=$fam; return 0; fi
  if [[ "$w" == bold && "$st" == italic ]]; then tries=( " Bold Italic" " BoldItalic" )
  elif [[ "$w" == bold ]]; then tries=( " Bold" )
  elif [[ "$st" == italic ]]; then tries=( " Italic" )
  fi
  tries+=( "" " Regular" " Bold" )
  for sfx in "${tries[@]}"; do
    for d in "$BM_HOME/fonts" /System/Library/Fonts/Supplemental /System/Library/Fonts /Library/Fonts "$HOME/Library/Fonts"; do
      for ext in ttf otf; do
        [[ -f "$d/$fam$sfx.$ext" ]] && { REPLY="$d/$fam$sfx.$ext"; return 0; }
      done
    done
  done
  return 1
}

# "bold italic 2.6pmin Georgia" -> FP_W FP_ST FP_SIZE FP_FAM
font_parts() {
  local a=() i=0
  read -r -a a <<<"$1"
  FP_W=normal; FP_ST=normal; FP_SIZE=""; FP_FAM=""
  while (( i < ${#a[@]} )); do
    case "${a[i]}" in
      bold) FP_W=bold ;; italic) FP_ST=italic ;; normal) ;;
      *) break ;;
    esac
    i=$(( i + 1 ))
  done
  FP_SIZE=${a[i]:-}; FP_FAM="${a[*]:$(( i + 1 ))}"
  return 0
}

# A text property through the cascade item -> band -> frame (REPLY; empty if unset). TP_SEC/TP_KEY:
# where it was found, for error messages.
tprop() {  # item key
  local s band
  igt "$1" band; band=$REPLY
  for s in "i_$1" $band frame; do
    lv "$s" "$2"
    if [[ -n "$REPLY" ]]; then TP_SEC=$s; TP_KEY=$2; return 0; fi
  done
  REPLY=""; TP_SEC=""; TP_KEY=""
  return 0
}

# One font property (family, size, weight, style): the longhand, else the font shorthand, per level
font_prop() {  # item family|size|weight|style
  local s band
  igt "$1" band; band=$REPLY
  for s in "i_$1" $band frame; do
    lv "$s" "font-$2"
    if [[ -n "$REPLY" ]]; then TP_SEC=$s; TP_KEY=font-$2; return 0; fi
    lv "$s" font
    if [[ -n "$REPLY" ]]; then
      font_parts "$REPLY"; TP_SEC=$s; TP_KEY=font
      [[ -n "$FP_SIZE" && -n "$FP_FAM" ]] || lerr "$s" font "'$REPLY' needs a size and a family, e.g. 2pmin Georgia"
      case "$2" in family) REPLY=$FP_FAM ;; size) REPLY=$FP_SIZE ;; weight) REPLY=$FP_W ;; style) REPLY=$FP_ST ;; esac
      return 0
    fi
  done
  TP_SEC=""; TP_KEY=""
  case "$2" in family) REPLY="DIN Alternate" ;; size) REPLY=1.7pmin ;; *) REPLY=normal ;; esac
  return 0
}

# A colour value: auto / auto-dim / contrast follow the background; others are checked once
LY_COLOURS_OK=" "
colour() {  # value section key -> REPLY
  case "$1" in
    auto)     REPLY=$FG ;;
    auto-dim) REPLY=$FG2 ;;
    contrast) if (( $(awk -v l="$LUM" 'BEGIN { print (l < 0.45) }') )); then REPLY="#FFFFFF"; else REPLY="#111111"; fi ;;
    *)
      if [[ "$LY_COLOURS_OK" != *" $1 "* ]]; then
        [[ -z "$(magick xc:"$1" null: 2>&1)" ]] || lerr "$2" "$3" "unknown colour '$1'"
        LY_COLOURS_OK="$LY_COLOURS_OK$1 "
      fi
      REPLY=$1 ;;
  esac
  return 0
}

# =====================================================================================================
# Items
# =====================================================================================================
# Where an item goes: region (top|bottom|left|right|photo), columns, row or anchor, absolute or not
ly_cell() {  # item
  local id=$1 c reg rest cs ce row=1
  lv "i_$id" cell; c=${REPLY:-bottom 1}
  read -r reg rest <<<"$c"
  case "$reg" in
    photo)
      rest=${rest:-center}
      case " $LY_ANCHORS " in *" $rest "*) ;; *) lerr "i_$id" cell "'$rest' is not a photo anchor ($LY_ANCHORS)" ;; esac
      ist "$id" anchor "$rest"; ist "$id" band "" ;;
    top|bottom|left|right)
      rest=${rest:-1}
      [[ "$rest" =~ ^([0-9]+)(-([0-9]+))?(/([0-9]+))?$ ]] ||
        lerr "i_$id" cell "'$c': expected e.g. bottom 2, bottom 1-3 or bottom 1-3/2"
      cs=${BASH_REMATCH[1]}; ce=${BASH_REMATCH[3]:-$cs}; row=${BASH_REMATCH[5]:-1}
      ist "$id" cs "$cs"; ist "$id" ce "$ce"; ist "$id" row "$row"; ist "$id" band "$reg" ;;
    *) lerr "i_$id" cell "'$reg' is not a region (top, bottom, left, right, photo)" ;;
  esac
  ist "$id" reg "$reg"
  lv "i_$id" position
  case "$REPLY" in absolute) ist "$id" abs 1 ;; ""|static) ist "$id" abs 0 ;; *) lerr "i_$id" position "position is absolute or left out" ;; esac
  # Margins
  local m=() mm
  lv "i_$id" margin; box4 "${REPLY:-0}" "i_$id" margin; m=($REPLY)
  PX_REF="" PX_EM=0
  igt "$id" size; PX_EM=${REPLY:-0}
  for mm in 0 1 2 3; do px "${m[mm]}" "i_$id" margin; m[mm]=$REPLY; done
  ist "$id" mt "${m[0]}"; ist "$id" mr "${m[1]}"; ist "$id" mb "${m[2]}"; ist "$id" ml "${m[3]}"
  return 0
}

# Text: content, font and colours; empty text removes the item. Rendered by ly_text_render.
ly_text_setup() {  # item
  local id=$1 t fam w st sz
  lv "i_$id" content; expand "$REPLY"; t=$REPLY
  t=$(ly_trim "$t")
  if [[ -z "$t" ]]; then ist "$id" gone 1; return 0; fi
  tprop "$id" text-transform
  case "$REPLY" in
    ""|none) ;; uppercase) t=$(upper "$t") ;; capitalize) t=$(titlecase "$t") ;;
    *) lerr "$TP_SEC" text-transform "text-transform is none, uppercase or capitalize" ;;
  esac
  ist "$id" text "$t"
  font_prop "$id" family; fam=$REPLY; local fsec=$TP_SEC fkey=$TP_KEY
  font_prop "$id" weight; w=$REPLY
  font_prop "$id" style; st=$REPLY
  font_file "$fam" "$w" "$st" || { if [[ -n "$fsec" ]]; then lerr "$fsec" "$fkey" "no font '$fam'"; else die "no font '$fam'"; fi; }
  ist "$id" font "$REPLY"
  font_prop "$id" size
  [[ "$REPLY" == *em || "$REPLY" == *% ]] && lerr "$TP_SEC" "$TP_KEY" "font sizes take pmin, pw, ph, fw or px"
  PX_REF="" px "$REPLY" "$TP_SEC" "$TP_KEY"; ist "$id" size "$REPLY"
  tprop "$id" color; colour "${REPLY:-auto}" "$TP_SEC" color; ist "$id" fill "$REPLY"
  return 0
}

# Render at a size (default: the item's), optionally wrapped to a width: I_*__img, w, h, shadows
ly_text_render() {  # item [size] [wrap-width]
  local id=$1 size wrap=${3:-} t font fill w h kern=0 ils=0 lh f opts
  igt "$id" size; size=${2:-$REPLY}
  igt "$id" text; t=$(im_text "$REPLY")
  igt "$id" font; font=$REPLY; igt "$id" fill; fill=$REPLY
  PX_EM=$size PX_REF=""
  tprop "$id" letter-spacing; [[ -n "$REPLY" ]] && { px "$REPLY" "$TP_SEC" "$TP_KEY"; kern=$REPLY; }
  tprop "$id" line-height
  if [[ -n "$REPLY" ]]; then
    [[ "$REPLY" =~ ^[0-9]+(\.[0-9]+)?$ ]] || lerr "$TP_SEC" line-height "line-height is a number, e.g. 1.2"
    lh=$(fr_milli "${REPLY}fr"); ils=$(( (lh - 1000) * size / 1000 ))
  fi
  ist "$id" kern "$kern"; ist "$id" psize "$size"
  opts=( -background none -font "$font" -pointsize "$size" )
  (( kern )) && opts+=( -kerning "$kern" )
  (( ils )) && opts+=( -interline-spacing "$ils" )
  f="$TMP/ly_${id//-/_}.miff"
  if [[ -n "$wrap" ]]; then
    # Tight leading clips the last line's descenders: add a blank line, then trim it away
    if (( ils < 0 )); then
      read -r w h < <(magick "${opts[@]}" -fill "$fill" -size "${wrap}x" caption:"$t"$'\n'" " -trim +repage \
                        -write "$f" -format "%w %h\n" info:)
    else
      read -r w h < <(magick "${opts[@]}" -fill "$fill" -size "${wrap}x" caption:"$t" -write "$f" -format "%w %h\n" info:)
    fi
  else
    read -r w h < <(magick "${opts[@]}" -fill "$fill" label:"$t" -write "$f" -format "%w %h\n" info:)
  fi
  ist "$id" img "$f"; ist "$id" w "$w"; ist "$id" h "$h"
  ist "$id" wrap "$wrap"; ist "$id" ils "$ils"
  return 0
}

# Shadows of a text item, once its size is final: a blurred copy per shadow, padded so the blur isn't
# cut off. I_*__shadows = lines of "file dx dy pad".
ly_text_shadows() {  # item
  local id=$1 t opts=() wrap ils k s d1 d2 bl col p sig shs=() i=0 f ssec
  tprop "$id" text-shadow; [[ -n "$REPLY" ]] || { ist "$id" shadows ""; return 0; }
  ssec=$TP_SEC; split_top "$REPLY"
  igt "$id" text; t=$(im_text "$REPLY")
  igt "$id" psize; PX_EM=$REPLY PX_REF=""
  opts=( -background none )
  igt "$id" font; opts+=( -font "$REPLY" -pointsize "$PX_EM" )
  igt "$id" kern; (( REPLY )) && opts+=( -kerning "$REPLY" )
  igt "$id" ils; (( REPLY )) && opts+=( -interline-spacing "$REPLY" )
  igt "$id" wrap; wrap=$REPLY
  igt "$id" img; f=$REPLY
  for s in "${SPLIT[@]}"; do
    read -r d1 d2 bl col <<<"$s"
    [[ -n "$col" ]] || lerr "$ssec" text-shadow "a shadow is <x> <y> <blur> <colour>"
    px "$d1" "$ssec" text-shadow; d1=$REPLY; px "$d2" "$ssec" text-shadow; d2=$REPLY
    px "$bl" "$ssec" text-shadow; sig=$REPLY; p=$(( (sig * 9 + 3) / 4 ))
    colour "$col" "$ssec" text-shadow; col=$REPLY
    if [[ -n "$wrap" ]]; then
      magick "${opts[@]}" -fill "$col" -size "${wrap}x" caption:"$t" -bordercolor none -border $p -blur 0x$sig "${f%.miff}_s$i.miff"
    else
      magick "${opts[@]}" -fill "$col" label:"$t" -bordercolor none -border $p -blur 0x$sig "${f%.miff}_s$i.miff"
    fi
    shs+=( "${f%.miff}_s$i.miff $d1 $d2 $p" ); i=$(( i + 1 ))
  done
  printf -v "I_${id//-/_}__shadows" '%s\n' "${shs[@]}"
  return 0
}

# Fit a text item into a width: wrap (caption), shrink (smaller size, one line) or clip
ly_text_fit() {  # item width
  local id=$1 maxw=$2 w size mode
  igt "$id" w; w=$REPLY
  (( maxw > 0 && w > maxw )) || return 0
  tprop "$id" overflow; mode=${REPLY:-wrap}
  case "$mode" in
    wrap)   ly_text_render "$id" "" "$maxw" ;;
    shrink) igt "$id" size; size=$(( REPLY * maxw / w )); ly_text_render "$id" "$size" ;;
    clip)   igt "$id" img; magick "$REPLY" -crop "${maxw}x+0+0" +repage "$REPLY"; ist "$id" w "$maxw" ;;
    *)      lerr "$TP_SEC" overflow "overflow is wrap, shrink or clip" ;;
  esac
  return 0
}

# The widest an item may be: its max-width (of the space it has), else that space
ly_maxw() {  # item space -> REPLY
  local id=$1 sp=$2 ml mr
  igt "$id" ml; ml=$REPLY; igt "$id" mr; mr=$REPLY
  sp=$(( sp - ml - mr ))
  tprop "$id" max-width
  if [[ -n "$REPLY" ]]; then
    local mw=$REPLY; igt "$id" size; PX_EM=${REPLY:-0} PX_REF=$sp px "$mw" "$TP_SEC" max-width
    (( REPLY < sp )) && sp=$REPLY
  fi
  REPLY=$sp
  return 0
}

ly_logo_setup() {  # item
  local id=$1 w h
  if [[ ! -f "$logo" ]]; then ist "$id" gone 1; return 0; fi
  lv "i_$id" height; PX_REF="" px "${REPLY:-1.8pmin}" "i_$id" height
  h=$(logo_height "$REPLY")
  prepare_logo "$h" "$TMP/ly_${id//-/_}.miff"
  ist "$id" img "$TMP/ly_${id//-/_}.miff"
  read -r w h < <(magick "$TMP/ly_${id//-/_}.miff" -format "%w %h\n" info:)
  ist "$id" w "$w"; ist "$id" h "$h"
  return 0
}

ly_rule_setup() {  # item
  local id=$1
  lv "i_$id" thickness; PX_REF="" px "${REPLY:-0.15pmin}" "i_$id" thickness
  (( REPLY > 0 )) || REPLY=1
  ist "$id" h "$REPLY"; ist "$id" w 0
  tprop "$id" color; colour "${REPLY:-auto}" "$TP_SEC" color; ist "$id" fill "$REPLY"
  return 0
}

# =====================================================================================================
# Layout
# =====================================================================================================
# Background canvas and ink (FG, FG2, DARK, LUM) from [frame] background / texture
ly_background() {
  local v a=() ang=135 lum
  lv frame background; v=${REPLY:-white}
  case "$v" in
    auto) canvas=( "xc:$(auto_colour)" ) ;;
    gradient\(*\))
      split_top "${v#gradient(}"; a=( "${SPLIT[@]}" ); a[${#a[@]}-1]=${a[${#a[@]}-1]%)}
      (( ${#a[@]} == 2 || ${#a[@]} == 3 )) || lerr frame background "gradient(<colour>, <colour>[, <angle>])"
      colour "${a[0]}" frame background; colour "${a[1]}" frame background
      [[ -n "${a[2]:-}" ]] && ang=${a[2]}
      canvas=( -define gradient:angle=$ang "gradient:${a[0]}-${a[1]}" ) ;;
    \$*) lerr frame background "$v isn't set here" ;;
    material\(*|frost*|film|dominant) lerr frame background "background $v is not available yet" ;;
    *)
      if [[ "$v" =~ ^([^-]+)-([^-]+)$ ]]; then   # "#A-#B" (a gradient from -b)
        colour "${BASH_REMATCH[1]}" frame background; colour "${BASH_REMATCH[2]}" frame background
        canvas=( -define gradient:angle=135 "gradient:$v" )
      else
        colour "$v" frame background; canvas=( "xc:$v" )
      fi ;;
  esac
  lum=$(magick -size 64x64 "${canvas[@]}" -resize 1x1\! -format "%[fx:luminance]" info:)
  canvas_ink "$lum"
  lv frame texture
  PAPER_ON=0; PAPER_K=0
  case "$REPLY" in
    ""|none) ;;
    paper) PAPER_K=$PAPER ;;
    paper\ *) PAPER_K=${REPLY#paper }
              [[ "$PAPER_K" =~ ^[0-9]+$ ]] && (( PAPER_K <= 30 )) || lerr frame texture "paper strength is 0 to 30" ;;
    *) lerr frame texture "texture is paper, paper <0–30> or none" ;;
  esac
  (( PAPER_K > 0 )) && PAPER_ON=1
  return 0
}

# Frame padding -> PAD_T PAD_R PAD_B PAD_L (pixels, or "auto" for a band sized by its content)
ly_padding() {
  local p=() i side
  lv frame padding; box4 "${REPLY:-0}" frame padding; p=($REPLY)
  FW=0
  for i in 1 3 0 2; do
    case $i in 0) side=PAD_T ;; 1) side=PAD_R ;; 2) side=PAD_B ;; 3) side=PAD_L ;; esac
    if [[ "${p[i]}" == auto ]]; then
      (( i == 0 || i == 2 )) || lerr frame padding "only the top and bottom can be auto"
      printf -v $side auto
    else
      [[ "${p[i]}" == *% || "${p[i]}" == *em ]] && lerr frame padding "padding takes pmin, pw, ph, fw or px"
      PX_REF="" px "${p[i]}" frame padding; printf -v $side %s "$REPLY"
    fi
    (( i == 3 )) && FW=$(( W + PAD_L + PAD_R ))
  done
  return 0
}

# Band boxes: outer (BX BY BW BH; BH may be -1 = auto) and inner (IX IY IW IH) for a band
ly_band_box() {  # band
  local p=() t r b l
  case "$1" in
    top)    BX=$PAD_L; BY=0; BW=$W; BH=$PAD_T ;;
    bottom) BX=$PAD_L; BY=-1; BW=$W; BH=$PAD_B ;;
    left)   BX=0; BY=-1; BW=$PAD_L; BH=$H ;;
    right)  BX=$(( PAD_L + W )); BY=-1; BW=$PAD_R; BH=$H ;;
  esac
  [[ "$BH" == auto ]] && BH=-1
  lv "$1" padding; box4 "${REPLY:-0}" "$1" padding; p=($REPLY)
  PX_REF="" px "${p[0]}" "$1" padding; t=$REPLY; px "${p[1]}" "$1" padding; r=$REPLY
  px "${p[2]}" "$1" padding; b=$REPLY; px "${p[3]}" "$1" padding; l=$REPLY
  BPT=$t; BPB=$b
  IX=$(( BX + l )); IW=$(( BW - l - r ))
  if (( BH >= 0 )); then IH=$(( BH - t - b )); else IH=-1; fi
  return 0
}

ly_resolve() {
  local id t band items c r n i reg anchor
  W=${W:?}; H=${H:?}
  ly_background
  ly_padding

  # Items: placement, then content (text measured at its natural size)
  PLAN_ITEMS=""
  for id in $LY_ITEMS; do
    for t in gone img w h x y shadows annot size; do ist "$id" $t ""; done
    lv "i_$id" type; t=$REPLY
    case "$t" in
      text) ly_cell "$id"; ly_text_setup "$id" ;;
      logo) ly_cell "$id"; ly_logo_setup "$id" ;;
      rule) ly_cell "$id"; ly_rule_setup "$id" ;;
      rect) ly_cell "$id" ;;
      *) lerr "i_$id" type "[$t] items are not available yet" ;;
    esac
    igt "$id" gone; [[ -n "$REPLY" ]] && continue
    igt "$id" band; band=$REPLY
    if [[ -n "$band" ]]; then
      case "$band" in top) n=$PAD_T ;; bottom) n=$PAD_B ;; left) n=$PAD_L ;; right) n=$PAD_R ;; esac
      [[ "$n" == 0 ]] && lerr "i_$id" cell "[$band] has no room: the frame's $band padding is 0"
    fi
    PLAN_ITEMS="$PLAN_ITEMS $id"
    [[ "$t" == text ]] && ly_text_render "$id"
    ly_cell "$id"   # again: margins in em need the font size
  done

  # Bands
  for band in top bottom left right; do ly_band "$band"; done
  [[ "$PAD_T" == auto ]] && PAD_T=$BAND_top_h
  [[ "$PAD_B" == auto ]] && PAD_B=$BAND_bottom_h
  FH=$(( PAD_T + H + PAD_B ))
  for band in top bottom left right; do ly_band_place "$band"; done
  ly_photo_place
  return 0
}

# Columns, wrapping and rows of one band; its auto height in BAND_<band>_h
ly_band() {  # band
  local band=$1 ids="" id cols spec n i a=() cs ce row w h sp rows rspec gap rgap
  printf -v "BAND_${band}_h" 0
  for id in $PLAN_ITEMS; do
    igt "$id" band; [[ "$REPLY" == "$band" ]] && ids="$ids $id"
  done
  [[ -n "$ids" ]] || return 0
  ly_band_box "$band"
  lv "$band" columns; spec=${REPLY:-1fr}; n=$(( $(wc -w <<<"$spec") ))
  lv "$band" column-gap; PX_REF="" px "${REPLY:-0}" "$band" column-gap; gap=$REPLY
  # Content widths of single-column items, per column (rules and rects have none)
  for (( i = 0; i < n; i++ )); do a[i]=0; done
  for id in $ids; do
    igt "$id" abs; [[ "$REPLY" == 1 ]] && continue
    igt "$id" cs; cs=$REPLY; igt "$id" ce; ce=$REPLY
    (( ce <= n )) || lerr "i_$id" cell "[$band] has only $n column(s)"
    (( cs == ce )) || continue
    igt "$id" w; w=${REPLY:-0}; igt "$id" ml; w=$(( w + REPLY )); igt "$id" mr; w=$(( w + REPLY ))
    (( w > a[cs-1] )) && a[cs-1]=$w
  done
  solve_tracks "$spec" "$IW" "$gap" "${a[*]}" "$band" columns; cols=($REPLY)
  # Column starts and cell widths; text wider than its cell wraps, shrinks or is clipped
  local x=$IX
  for (( i = 0; i < n; i++ )); do printf -v "COL_${band}_$(( i + 1 ))" %s "$x"; x=$(( x + cols[i] + gap )); done
  for id in $ids; do
    igt "$id" cs; cs=$REPLY; igt "$id" ce; ce=$REPLY
    igt "$id" abs
    if [[ "$REPLY" == 1 ]]; then sp=$BW
    else sp=$(( gap * (ce - cs) )); for (( i = cs; i <= ce; i++ )); do sp=$(( sp + cols[i-1] )); done; fi
    ist "$id" cellw "$sp"
    lv "i_$id" type
    case "$REPLY" in
      text) ly_maxw "$id" "$sp"; ly_text_fit "$id" "$REPLY" ;;
      rule) igt "$id" ml; w=$(( sp - REPLY )); igt "$id" mr; ist "$id" w $(( w - REPLY )) ;;
    esac
  done
  # Rows: content height of each cell's stack
  lv "$band" rows; rspec=${REPLY:-auto}
  lv "$band" row-gap; PX_REF="" px "${REPLY:-0}" "$band" row-gap; rgap=$REPLY
  local nr; nr=$(( $(wc -w <<<"$rspec") )); a=()
  for id in $ids; do igt "$id" row; (( REPLY > nr )) && nr=$REPLY; done
  local rs=($rspec); for (( i = ${#rs[@]}; i < nr; i++ )); do rs[i]=auto; done
  for (( i = 0; i < nr; i++ )); do a[i]=0; done
  ly_stacks "$band" "$ids"
  for c in $STACK_CELLS; do
    row=${c##*/}; h=${c#*:}; h=${h%%/*}
    (( h > a[row-1] )) && a[row-1]=$h
  done
  solve_tracks "${rs[*]}" "$IH" "$rgap" "${a[*]}" "$band" rows; rows=($REPLY)
  local y=0
  for (( i = 0; i < nr; i++ )); do printf -v "ROW_${band}_$(( i + 1 ))" %s "$y"; printf -v "ROWH_${band}_$(( i + 1 ))" %s "${rows[i]}"; y=$(( y + rows[i] + rgap )); done
  y=$(( y - rgap ))
  printf -v "BAND_${band}_h" %s $(( y + BPT + BPB ))
  printf -v "BAND_${band}_ids" %s "$ids"
  return 0
}

# Stack heights per cell: STACK_CELLS = "cs-ce:height/row …"
ly_stacks() {  # band ids
  local id key cells="" h ab
  STACK_CELLS=""
  for id in $2; do
    igt "$id" abs; [[ "$REPLY" == 1 ]] && continue
    lv "i_$id" type; [[ "$REPLY" == rect ]] && continue
    igt "$id" cs; key=$REPLY; igt "$id" ce; key="$key-$REPLY"; igt "$id" row; key="$key@$REPLY"
    igt "$id" h; h=${REPLY:-0}; igt "$id" mt; h=$(( h + REPLY )); igt "$id" mb; h=$(( h + REPLY ))
    local v="STK_${1}_${key//[-@]/_}"
    printf -v "$v" %s $(( ${!v:-0} + h ))
    [[ " $cells " == *" $key "* ]] || cells="$cells $key"
  done
  for key in $cells; do
    local v="STK_${1}_${key//[-@]/_}"
    STACK_CELLS="$STACK_CELLS ${key%@*}:${!v}/${key#*@}"
    unset "$v"
  done
  return 0
}

# Positions of a band's items: stacks in their cells, absolute ones in the band
ly_band_place() {  # band
  local band=$1 ids id cs ce row cx cy cw ch y0 align just x y w h sh key v
  v="BAND_${band}_ids"; ids=${!v-}
  [[ -n "$ids" ]] || return 0
  ly_band_box "$band"
  case "$band" in
    top) BY=0; BH=$PAD_T ;; bottom) BY=$(( PAD_T + H )); BH=$PAD_B ;; left|right) BY=$PAD_T ;;
  esac
  IY=$(( BY + BPT )); IH=$(( BH - BPT - BPB ))
  lv "$band" align-items; align=${REPLY:-center}
  case "$align" in start|center|end) ;; *) lerr "$band" align-items "align-items is start, center or end" ;; esac
  ly_stacks "$band" "$ids"
  local c used
  for c in $STACK_CELLS; do
    key=${c%%:*}; sh=${c#*:}; sh=${sh%%/*}; row=${c##*/}; cs=${key%-*}; ce=${key#*-}
    v="ROW_${band}_$row"; cy=$(( IY + ${!v} )); v="ROWH_${band}_$row"; ch=${!v}
    # A single auto row fills the band
    v="ROW_${band}_2"; [[ -z "${!v-}" ]] && ch=$IH
    case "$align" in start) y0=$cy ;; center) y0=$(( cy + (ch - sh) / 2 )) ;; end) y0=$(( cy + ch - sh )) ;; esac
    v="COL_${band}_$cs"; cx=${!v}
    for id in $ids; do
      igt "$id" abs; [[ "$REPLY" == 1 ]] && continue
      lv "i_$id" type; [[ "$REPLY" == rect ]] && continue
      igt "$id" cs; [[ "$REPLY" == "$cs" ]] || continue
      igt "$id" ce; [[ "$REPLY" == "$ce" ]] || continue
      igt "$id" row; [[ "$REPLY" == "$row" ]] || continue
      igt "$id" cellw; cw=$REPLY
      igt "$id" mt; y0=$(( y0 + REPLY ))
      ly_justify "$id" "$cx" "$cw"
      ist "$id" y "$y0"
      igt "$id" h; y0=$(( y0 + REPLY )); igt "$id" mb; y0=$(( y0 + REPLY ))
    done
  done
  for id in $ids; do
    igt "$id" abs; [[ "$REPLY" == 1 ]] && ly_absolute "$id" "$BX" "$BY" "$BW" "$BH"
    lv "i_$id" type; [[ "$REPLY" == rect ]] && ly_rect "$id" "$BX" "$BY" "$BW" "$BH"
  done
  printf -v "BANDBOX_$band" '%s' "$BX $BY $BW $BH"
  return 0
}

ly_justify() {  # item cell-x cell-w -> sets x
  local id=$1 w ml mr
  igt "$id" w; w=${REPLY:-0}; igt "$id" ml; ml=$REPLY; igt "$id" mr; mr=$REPLY
  lv "i_$id" justify
  case "${REPLY:-start}" in
    start)  ist "$id" x $(( $2 + ml )) ;;
    center) ist "$id" x $(( $2 + (ml + $3 - mr - w) / 2 )) ;;
    end)    ist "$id" x $(( $2 + $3 - mr - w )) ;;
    *) lerr "i_$id" justify "justify is start, center or end" ;;
  esac
  return 0
}

# An absolute item in its region box: left/right/top/bottom, else justify / centred.
# Text with vertical-align = baseline is drawn by -annotate at that baseline (like the classic strip).
ly_absolute() {  # item rx ry rw rh
  local id=$1 rx=$2 ry=$3 rw=$4 rh=$5 w h k
  igt "$id" w; w=${REPLY:-0}; igt "$id" h; h=${REPLY:-0}
  igt "$id" size; PX_EM=${REPLY:-0}
  local L R T Bt
  PX_REF=$rw; lv "i_$id" left;   L=$REPLY;  [[ -n "$L" ]] && { px "$L" "i_$id" left; L=$REPLY; }
  PX_REF=$rw; lv "i_$id" right;  R=$REPLY;  [[ -n "$R" ]] && { px "$R" "i_$id" right; R=$REPLY; }
  PX_REF=$rh; lv "i_$id" top;    T=$REPLY;  [[ -n "$T" ]] && { px "$T" "i_$id" top; T=$REPLY; }
  PX_REF=$rh; lv "i_$id" bottom; Bt=$REPLY; [[ -n "$Bt" ]] && { px "$Bt" "i_$id" bottom; Bt=$REPLY; }
  if [[ -n "$L" ]]; then ist "$id" x $(( rx + L ))
  elif [[ -n "$R" ]]; then ist "$id" x $(( rx + rw - R - w ))
  else ly_justify "$id" "$rx" "$rw"; fi
  if [[ -n "$T" ]]; then ist "$id" y $(( ry + T ))
  elif [[ -n "$Bt" ]]; then ist "$id" y $(( ry + rh - Bt - h ))
  else ist "$id" y $(( ry + (rh - h) / 2 )); fi
  lv "i_$id" vertical-align
  if [[ "$REPLY" == baseline ]]; then
    lv "i_$id" type; [[ "$REPLY" == text ]] || lerr "i_$id" vertical-align "vertical-align = baseline is for text"
    [[ -n "$Bt" ]] || lerr "i_$id" vertical-align "vertical-align = baseline needs bottom"
    # -annotate offsets: from the image's left or right edge, and from its bottom edge to the baseline
    if [[ -n "$R" ]]; then ist "$id" annot "southeast +$(( FW - rx - rw + R ))+$(( FH - ry - rh + Bt ))"
    else ist "$id" annot "southwest +$(( rx + ${L:-0} ))+$(( FH - ry - rh + Bt ))"; fi
  fi
  return 0
}

# A rectangle: inset from its region's edges (negative = outside)
ly_rect() {  # item rx ry rw rh
  local id=$1 p=() i
  lv "i_$id" inset; box4 "${REPLY:-0}" "i_$id" inset; p=($REPLY)
  for i in 0 2; do PX_REF=$5 px "${p[i]}" "i_$id" inset; p[i]=$REPLY; done
  for i in 1 3; do PX_REF=$4 px "${p[i]}" "i_$id" inset; p[i]=$REPLY; done
  ist "$id" x $(( $2 + p[3] )); ist "$id" y $(( $3 + p[0] ))
  ist "$id" w $(( $4 - p[1] - p[3] )); ist "$id" h $(( $5 - p[0] - p[2] ))
  return 0
}

# Items on the photo: stacks at the nine anchors, absolute items and rectangles
ly_photo_place() {
  local id a stk y0 sh w t
  for a in $LY_ANCHORS; do
    sh=0; stk=""
    for id in $PLAN_ITEMS; do
      igt "$id" anchor; [[ "$REPLY" == "$a" ]] || continue
      igt "$id" abs; [[ "$REPLY" == 1 ]] && continue
      lv "i_$id" type; t=$REPLY
      [[ "$t" == rect ]] && continue
      [[ "$t" == text ]] && { ly_maxw "$id" "$W"; ly_text_fit "$id" "$REPLY"; }
      [[ "$t" == rule ]] && { igt "$id" ml; w=$(( W - REPLY )); igt "$id" mr; ist "$id" w $(( w - REPLY )); }
      igt "$id" h; sh=$(( sh + REPLY )); igt "$id" mt; sh=$(( sh + REPLY )); igt "$id" mb; sh=$(( sh + REPLY ))
      stk="$stk $id"
    done
    [[ -n "$stk" ]] || continue
    case "$a" in
      top-*) y0=$PAD_T ;; bottom-*) y0=$(( PAD_T + H - sh )) ;; *) y0=$(( PAD_T + (H - sh) / 2 )) ;;
    esac
    for id in $stk; do
      igt "$id" mt; y0=$(( y0 + REPLY ))
      igt "$id" w; w=${REPLY:-0}
      case "$a" in
        *left)            igt "$id" ml; ist "$id" x $(( PAD_L + REPLY )) ;;
        *right)           igt "$id" mr; ist "$id" x $(( PAD_L + W - REPLY - w )) ;;
        *)                ly_justify_center "$id" ;;
      esac
      ist "$id" y "$y0"
      igt "$id" h; y0=$(( y0 + REPLY )); igt "$id" mb; y0=$(( y0 + REPLY ))
    done
  done
  for id in $PLAN_ITEMS; do
    igt "$id" reg; [[ "$REPLY" == photo ]] || continue
    igt "$id" abs; [[ "$REPLY" == 1 ]] && ly_absolute "$id" "$PAD_L" "$PAD_T" "$W" "$H"
    lv "i_$id" type; [[ "$REPLY" == rect ]] && ly_rect "$id" "$PAD_L" "$PAD_T" "$W" "$H"
  done
  return 0
}
ly_justify_center() {  # item: centred on the frame like gravity north (same as on the photo when the sides match)
  local w ml mr; igt "$1" w; w=${REPLY:-0}; igt "$1" ml; ml=$REPLY; igt "$1" mr; mr=$REPLY
  ist "$1" x $(( PAD_L + (ml + W - mr - w) / 2 ))
  return 0
}

# =====================================================================================================
# Plan and drawing
# =====================================================================================================
ly_plan() {
  local id band v
  echo "frame - 0 0 $FW $FH"
  echo "photo - $PAD_L $PAD_T $W $H"
  for band in top bottom left right; do
    v="BANDBOX_$band"; [[ -n "${!v-}" ]] && echo "band $band ${!v}"
  done
  for id in $PLAN_ITEMS; do
    lv "i_$id" type; v=$REPLY
    igt "$id" x; local x=$REPLY; igt "$id" y; local y=$REPLY; igt "$id" w; local w=$REPLY; igt "$id" h
    echo "$v $id $x $y $w $REPLY"
  done
  return 0
}

ly_draw() {
  local id t x y w h f s a sx sy p sf
  paper   # (adds the texture to the canvas)
  args=( -size ${FW}x${FH} "${canvas[@]}" -gravity northwest )
  for id in $PLAN_ITEMS; do   # rectangles under the photo
    lv "i_$id" type; [[ "$REPLY" == rect ]] || continue
    lv "i_$id" under-photo; [[ "$REPLY" == yes ]] && ly_draw_rect "$id"
  done
  args+=( \( "$in" -auto-orient \) -gravity northwest -geometry +$PAD_L+$PAD_T -composite )
  for id in $PLAN_ITEMS; do
    lv "i_$id" type; t=$REPLY
    igt "$id" x; x=$REPLY; igt "$id" y; y=$REPLY; igt "$id" w; w=$REPLY; igt "$id" h; h=$REPLY
    case "$t" in
      text)
        igt "$id" annot; a=$REPLY
        if [[ -n "$a" ]]; then
          igt "$id" font; f=$REPLY; igt "$id" text; s=$(im_text "$REPLY")
          local k; igt "$id" kern; k=$REPLY
          igt "$id" psize; local ps=$REPLY; igt "$id" fill
          args+=( -font "$f" -pointsize "$ps" -fill "$REPLY" )
          (( k )) && args+=( -kerning "$k" )
          args+=( -gravity "${a%% *}" -annotate "${a#* }" "$s" )
          (( k )) && args+=( -kerning 0 )
        else
          ly_text_shadows "$id"; igt "$id" shadows
          while read -r sf sx sy p; do
            [[ -n "$sf" ]] && args+=( "$sf" -gravity northwest -geometry +$(( x + sx - p ))+$(( y + sy - p )) -composite )
          done <<<"$REPLY"
          igt "$id" img; args+=( "$REPLY" -gravity northwest -geometry +$x+$y -composite )
        fi ;;
      logo) igt "$id" img; args+=( "$REPLY" -gravity northwest -geometry +$x+$y -composite ) ;;
      rule) igt "$id" fill; args+=( -fill "$REPLY" -draw "rectangle $x,$y $(( x + w - 1 )),$(( y + h - 1 ))" ) ;;
      rect) lv "i_$id" under-photo; [[ "$REPLY" == yes ]] || ly_draw_rect "$id" ;;
    esac
  done
  return 0
}

ly_draw_rect() {  # item
  local id=$1 x y w h fill stroke sw
  igt "$id" x; x=$REPLY; igt "$id" y; y=$REPLY; igt "$id" w; w=$REPLY; igt "$id" h; h=$REPLY
  lv "i_$id" fill; fill=$REPLY; lv "i_$id" stroke; stroke=$REPLY
  if [[ -n "$fill" && "$fill" != none ]]; then
    colour "$fill" "i_$id" fill
    args+=( -fill "$REPLY" -draw "rectangle $x,$y $(( x + w - 1 )),$(( y + h - 1 ))" )
  fi
  if [[ -n "$stroke" && "$stroke" != none ]]; then
    colour "$stroke" "i_$id" stroke; stroke=$REPLY
    lv "i_$id" stroke-width; PX_REF="" px "${REPLY:-1px}" "i_$id" stroke-width; sw=$REPLY
    # The stroke lies inside the box: its outer edge is the box edge
    args+=( -fill none -stroke "$stroke" -strokewidth $sw
            -draw "rectangle $(( x + sw / 2 )),$(( y + sw / 2 )) $(( x + w - sw / 2 - 1 )),$(( y + h - sw / 2 - 1 ))"
            -stroke none )
  fi
  return 0
}

# One photo through a layout: read, resolve, then print the plan or draw and write
frame_layout() {
  KIND=layout; INSET=0; FILM=0; MUSEUM=0; POSTER=0; POSTCARD=0; COVER=""
  LOGO_ON=0; local id; for id in $LY_ITEMS; do lv "i_$id" type; [[ "$REPLY" == logo ]] && LOGO_ON=1; done
  read_meta
  read -r W H < <(magick "$in" -auto-orient -format "%w %h\n" info:)
  S=$(( W < H ? W : H ))
  ly_resolve
  if (( PLAN )); then ly_plan; return 0; fi
  ly_draw
  write_out
  return 0
}
