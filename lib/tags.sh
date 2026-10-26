# bordermagick — tags: the values a layout can print, read from the photo in one exiftool call, and the
# template engine that fills them into text ("{place} ∙ {date}"). See docs/layouts.md §7.
# Sourced by bordermagick; only defines functions. Uses SEP and brand_name from the script.

# Public tags, in the order --tags prints them
TAG_NAMES="title city country place date make model brand body lens focal aperture shutter iso exposure film frame filename"
# Raw EXIF fields read for them (X_<field>); Saturation and FilmMode are Fujifilm's
EXIF_FIELDS="Make Model LensID LensModel FocalLength FNumber ExposureTime ISO Title City Country DateTimeOriginal Saturation FilmMode"

# Join the non-empty arguments with " ∙ "
join_sep() { local out="" a; for a in "$@"; do [[ -n "$a" ]] && out="${out:+$out $SEP }$a"; done; echo "$out"; }
titlecase() { perl -CS -Mutf8 -pe 's/(\w+)/\u\L$1/g' <<<"$1"; }   # "PRO NEG. HI" -> "Pro Neg. Hi", "ACROS+R" -> "Acros+R"

# --- Reading: one exiftool call; X_<field> = raw values, T_<tag> = the tags
read_tags() {  # photo [index in batch]
  local in=$1 f line name val
  for f in $EXIF_FIELDS; do printf -v "X_$f" '%s' ""; done
  # -S prints "Field: value", one line per field that has a value, with the same priority as -s3
  while IFS= read -r line; do
    name=${line%%: *}; val=${line#*: }
    case " $EXIF_FIELDS " in *" $name "*) printf -v "X_$name" '%s' "$val" ;; esac
  done < <(exiftool -q -m -S -d '%Y:%m:%d %H:%M:%S' -Make -Model -LensID -LensModel -FocalLength -FNumber \
             -ExposureTime -ISO -Title -City -Country -DateTimeOriginal -FujiFilm:Saturation -FujiFilm:FilmMode \
             "$in" || true)

  T_make=$X_Make; T_model=$X_Model; T_title=$X_Title; T_city=$X_City; T_country=$X_Country
  # LensID (exiftool's offline lens database) first; fall back to the raw EXIF LensModel,
  # adding the space some makers omit between focal length and aperture ("18-55mmF2.8" -> "18-55mm F2.8")
  T_lens=$X_LensID
  if [[ -z "$T_lens" || "$T_lens" == Unknown* ]]; then
    T_lens=""; [[ -n "$X_LensModel" ]] && T_lens=$(sed -E 's/([0-9])mm ?([Ff]\/?[0-9])/\1mm \2/' <<<"$X_LensModel")
  fi
  T_focal=${X_FocalLength/.0/}
  T_aperture=${X_FNumber:+ƒ/$X_FNumber}; T_shutter=${X_ExposureTime:+${X_ExposureTime}s}; T_iso=${X_ISO:+ISO $X_ISO}
  T_exposure=$(join_sep "$T_focal" "$T_aperture" "$T_shutter" "$T_iso")
  # The city appears as the place unless the title has to fall back to it
  T_place=""; [[ -n "$T_title" ]] && T_place=$T_city
  T_date=$(tag_date "%-d %B %Y")
  T_filename=${in##*/}; T_filename=${T_filename%.*}
  T_frame=$(frame_number "$in" "${2:-1}")

  # Logo key (not a tag): "NIKON CORPORATION" -> nikon, "FUJIFILM" -> fujifilm, etc. Newer Pentax bodies
  # report "RICOH IMAGING COMPANY" as the maker, so the model decides there.
  T_key=$(awk '{print tolower($1)}' <<<"$T_make")
  [[ "$T_key" == ricoh && "$T_model" == PENTAX* ]] && T_key=pentax
  [[ "$T_key" == eastman ]] && T_key=kodak   # "EASTMAN KODAK COMPANY"
  if [[ "$T_key" == apple ]]; then            # iPhone / iPad have their own wordmarks
    case "$T_model" in iPhone*) T_key=iphone ;; iPad*) T_key=ipad ;; esac
  fi
  camera_body
  # Film simulation: T_FILM as printed on film edges (PROVIA), T_film for text (Provia)
  T_FILM=$(film_name); T_film=""; [[ -n "$T_FILM" ]] && T_film=$(titlecase "$T_FILM")
  return 0
}

# Date in any strftime format, in English like exiftool's -d; empty without a valid date
tag_date() {  # format
  [[ -n "$X_DateTimeOriginal" ]] || return 0
  perl -MPOSIX -e 'setlocale(LC_TIME, "C"); my ($f, $d) = @ARGV;
    exit unless $d =~ /^(\d{4}):(\d\d):(\d\d)(?: (\d\d):(\d\d):(\d\d))?/ && $2 >= 1 && $2 <= 12 && $3 >= 1 && $3 <= 31;
    print strftime($f, $6 // 0, $5 // 0, $4 // 0, $3, $2 - 1, $1 - 1900)' "$1" "$X_DateTimeOriginal"
}

# Frame number: the last number in the file name ("…_33.jpg" -> 33), else the photo's place in the batch
frame_number() {  # photo index
  local num
  num=$(basename "${1%.*}" | { grep -oE '[0-9]+' || true; } | tail -1)
  if [[ -n "$num" ]]; then echo $(( 10#$num )); else echo "$2"; fi
}

# Camera body with the brand in front unless the model already names it: "Fujifilm X-T20", "Sony ILCE-7M4",
# but "Canon EOS R6", "LEICA Q3". Sets T_brand and T_body.
camera_body() {
  T_brand=""; [[ -n "$T_key" ]] && T_brand=$(brand_name "$T_key" | awk '{print $1}')
  [[ "$T_key" == om ]] && T_brand="OM System"
  T_body="$T_model"
  if [[ -n "$T_brand" && -n "$T_model" ]] && ! grep -qi "^$(awk '{print $1}' <<<"$T_make")" <<<"$T_model" &&
     ! grep -qi "^$T_key" <<<"$T_model"; then T_body="$T_brand $T_model"; fi
  return 0
}

# Fujifilm film simulation as printed on film edges (PROVIA, CLASSIC CHROME …); empty if unknown.
# Black-and-white modes are recorded under Saturation, colour ones under FilmMode.
film_name() {
  case "$X_Saturation" in
    "Acros Red"*) echo "ACROS+R"; return ;;  "Acros Yellow"*) echo "ACROS+Ye"; return ;;
    "Acros Green"*) echo "ACROS+G"; return ;; Acros*) echo "ACROS"; return ;;
    *Sepia*) echo "SEPIA"; return ;;
    "B&W Red"*) echo "MONOCHROME+R"; return ;; "B&W Yellow"*) echo "MONOCHROME+Ye"; return ;;
    "B&W Green"*) echo "MONOCHROME+G"; return ;; *"B&W"*) echo "MONOCHROME"; return ;;
  esac
  case "$X_FilmMode" in
    "") ;;
    *Provia*) echo "PROVIA" ;;            *Astia*) echo "ASTIA" ;;            *Velvia*) echo "VELVIA" ;;
    "Pro Neg. Std"*) echo "PRO NEG. STD" ;; "Pro Neg. Hi"*) echo "PRO NEG. HI" ;;
    "Classic Chrome"*) echo "CLASSIC CHROME" ;;
    *"Bleach Bypass"*) echo "ETERNA BLEACH BYPASS" ;; Eterna*) echo "ETERNA" ;;
    "Classic Neg"*) echo "CLASSIC NEG." ;; "Nostalgic Neg"*) echo "NOSTALGIC NEG." ;;
    Reala*) echo "REALA ACE" ;;
    *) sed -E 's#^F[0-9]+[a-z]?/##' <<<"$X_FilmMode" | tr '[:lower:]' '[:upper:]' ;;   # older "F1/Studio Portrait" etc.
  esac
}

print_tags() {  # --tags: every public tag of the photo just read
  local t v
  for t in $TAG_NAMES; do
    v="T_$t"; v=${!v}
    if [[ -n "$v" ]]; then printf '%-9s %s\n' "$t:" "$v"; else echo "$t:"; fi
  done
}

# =====================================================================================================
# Templates. A template is literal text with tags {a|b|c} (first one with a value; {date:%Y} formats the
# date) and optional groups […] (dropped when a tag directly inside is empty). Text between two tags or
# groups is a separator: written only when there is a value on both sides, so "{a} ∙ {b} ∙ {c}" with b
# empty gives "a ∙ c". Text before the first and after the last tag or group is always kept.
# Escapes: \n (line break), \{ \} \[ \] \\. The result is left in REPLY.
# =====================================================================================================
expand() {  # template
  TPL=$1; TPL_I=0
  tpl_seq ""
  REPLY=$TPL_OUT
}

# Parse up to the closing character (empty: the end); leaves TPL_OUT, and TPL_EMPTY=1 if a tag directly
# in this sequence had no value
tpl_seq() {  # closing
  local close=$1 c out="" pend="" seen=0 emitted=0 empty=0 v
  while (( TPL_I < ${#TPL} )); do
    c=${TPL:TPL_I:1}; TPL_I=$(( TPL_I + 1 ))
    case "$c" in
      \\)
        c=${TPL:TPL_I:1}; TPL_I=$(( TPL_I + 1 ))
        case "$c" in
          n) pend+=$'\n' ;;
          '{'|'}'|'['|']'|\\) pend+=$c ;;
          *) pend+="\\$c" ;;
        esac ;;
      '{'|'[')
        if [[ "$c" == '{' ]]; then
          tpl_tag; v=$TPL_OUT; [[ -z "$v" ]] && empty=1
        else
          tpl_seq "]"; v=$TPL_OUT; (( TPL_EMPTY )) && v=""
        fi
        # Leading text always; a separator only between two values
        if (( ! seen )) || { [[ -n "$v" ]] && (( emitted )); }; then out+=$pend; fi
        pend=""; seen=1
        if [[ -n "$v" ]]; then out+=$v; emitted=1; fi ;;
      ']')
        [[ "$close" == "]" ]] || die "template '$TPL': ']' without '['"
        TPL_OUT=$out$pend; TPL_EMPTY=$empty; return 0 ;;
      '}') die "template '$TPL': '}' without '{'" ;;
      *) pend+=$c ;;
    esac
  done
  [[ -z "$close" ]] || die "template '$TPL': '[' without ']'"
  TPL_OUT=$out$pend; TPL_EMPTY=$empty
}

# One {…}: names separated by |, an optional :format (date only); leaves the value in TPL_OUT
tpl_tag() {
  local rest=${TPL:TPL_I} spec names fmt="" n v
  [[ "$rest" == *"}"* ]] || die "template '$TPL': '{' without '}'"
  spec=${rest%%\}*}; TPL_I=$(( TPL_I + ${#spec} + 1 ))
  names=$spec
  if [[ "$spec" == *:* ]]; then names=${spec%%:*}; fmt=${spec#*:}; fi
  [[ -z "$fmt" || "$names" == date ]] || die "template '$TPL': a :format only works on {date}"
  TPL_OUT=""
  for n in ${names//|/ }; do
    case " $TAG_NAMES " in *" $n "*) ;; *) die "template '$TPL': unknown tag {$n}" "Tags: $TAG_NAMES" ;; esac
    if [[ -n "$fmt" ]]; then v=$(tag_date "$fmt"); else v="T_$n"; v=${!v}; fi
    if [[ -n "$v" ]]; then TPL_OUT=$v; return 0; fi
  done
  [[ -n "$names" ]] || die "template '$TPL': empty {}"
  return 0
}
