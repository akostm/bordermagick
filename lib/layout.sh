# bordermagick — layout files: find, parse, merge (extends) and check them. See docs/layouts.md §2, §5, §9.
# Sourced by bordermagick; only defines functions. Uses die from the script.
#
# A loaded layout lives in plain variables (bash 3.2 has no associative arrays). Section ids are layout,
# frame, photo, top, bottom, left, right, and i_<name> for items, with "-" written as "_":
#   LYV_<sec>__<key>   value             LYK_<sec>   key names in order
#   LYS_<sec>__<key>   file:line         LY_ITEMS    item names in order; LYV_i_<name>__type = item type
# layout_get SECTION KEY reads a value. LY_VAR_border / LY_VAR_paper fill in $border / $paper.

LY_TEXT_KEYS="color font font-family font-size font-weight font-style letter-spacing line-height text-transform text-shadow max-width overflow"
LY_ITEM_KEYS="cell justify margin position left right top bottom vertical-align remove"
LY_BANDS="top bottom left right"
LY_TYPES="text logo rule rect edge-print image"
LY_PLANNED="swatches histogram"

ly_keys() {  # section type -> the keys it allows
  case "$1" in
    layout)     echo "name category description extends" ;;
    frame)      echo "padding background texture text-effect $LY_TEXT_KEYS" ;;
    photo)      echo "effect" ;;
    top|bottom|left|right) echo "columns rows column-gap row-gap padding align-items $LY_TEXT_KEYS" ;;
    text)       echo "$LY_ITEM_KEYS content $LY_TEXT_KEYS" ;;
    logo)       echo "$LY_ITEM_KEYS height" ;;
    rule)       echo "$LY_ITEM_KEYS thickness color" ;;
    rect)       echo "$LY_ITEM_KEYS inset fill stroke stroke-width under-photo" ;;
    edge-print) echo "$LY_ITEM_KEYS" ;;
    image)      echo "$LY_ITEM_KEYS src height opacity" ;;
  esac
}

ly_trim() {  # text -> without surrounding whitespace
  local t=$1
  t=${t#"${t%%[![:space:]]*}"}; t=${t%"${t##*[![:space:]]}"}
  echo "$t"
}

layout_reset() {
  local v
  for v in $(compgen -v LYV_) $(compgen -v LYS_) $(compgen -v LYK_); do unset "$v"; done
  LY_ITEMS=""; LY_CHAIN=""; LY_FILES=""
}

layout_find() {  # name [file] -> path along LAYOUT_PATH (after file's folder, if given)
  local d skip=${2:+${2%/*}}
  for d in ${LAYOUT_PATH//:/ }; do
    if [[ -n "$skip" ]]; then [[ "$d" == "$skip" ]] && skip=""; continue; fi
    [[ -f "$d/$1.layout" ]] && { echo "$d/$1.layout"; return 0; }
  done
  return 1
}

layout_list() {  # every layout name along LAYOUT_PATH, once
  local d f seen=" "
  for d in ${LAYOUT_PATH//:/ }; do
    for f in "$d"/*.layout; do
      [[ -f "$f" ]] || continue
      f=${f##*/}; f=${f%.layout}
      [[ "$seen" == *" $f "* ]] || seen="$seen$f "
    done
  done
  echo $seen
}

ly_available() {  # hint for errors
  local l; l=$(layout_list)
  if [[ -n "$l" ]]; then echo "Layouts: $l"; else echo "No layout files in ${LAYOUT_PATH//:/ or }."; fi
}

layout_get() {  # section key
  local v="LYV_${1//-/_}__${2//-/_}"
  echo "${!v-}"
}

ly_set() {  # section key value source
  local s=${1//-/_} k=${2//-/_} list
  list="LYK_$s"; list=${!list-}
  [[ " $list " == *" $2 "* ]] || printf -v "LYK_$s" '%s' "${list:+$list }$2"
  printf -v "LYV_${s}__$k" '%s' "$3"
  printf -v "LYS_${s}__$k" '%s' "$4"
}

# $border and $paper from the command line; other $names are errors. Unset variables stay as written.
ly_vars() {  # value where -> REPLY
  local v=$1 out="" name val
  while [[ "$v" == *'$'* ]]; do
    out+=${v%%\$*}; v=${v#*\$}
    name=$(expr "$v" : '\([a-z][a-z-]*\)' || true)
    if [[ -z "$name" ]]; then out+='$'; continue; fi
    case "$name" in
      border|paper)
        val="LY_VAR_$name"
        if [[ -n "${!val-}" ]]; then out+=${!val}; else out+="\$$name"; fi ;;
      *) die "$2: unknown variable \$$name" "Variables: \$border, \$paper" ;;
    esac
    v=${v:${#name}}
  done
  REPLY=$out$v
}

layout_load() {  # name: load it, with everything it extends
  layout_reset
  ly_load "$1"
  # remove = yes drops an item (inherited or not)
  local i items=""
  for i in $LY_ITEMS; do
    [[ "$(layout_get "i_$i" remove)" == yes ]] || items="${items:+$items }$i"
  done
  LY_ITEMS=$items
  printf -v LYV_layout__name '%s' "$1"   # the name is the file's, never inherited
}

ly_load() {  # name [file that extends it under the same name]
  local name=$1 file n=0 line raw sec="" stype="" key val parent="" t
  local recs=()
  if [[ -n "${2:-}" ]]; then
    file=$(layout_find "$name" "$2") || die "$2: extends $name, but there is no other $name.layout to extend"
  else
    file=$(layout_find "$name") || die "no layout '$name'" "$(ly_available)"
  fi
  [[ $'\n'"$LY_FILES"$'\n' != *$'\n'"$file"$'\n'* ]] ||
    die "layouts extend each other in a loop: $(echo $LY_CHAIN | sed 's/ / → /g') → $name"
  LY_CHAIN="$LY_CHAIN $name"; LY_FILES="$LY_FILES"$'\n'"$file"

  # Parse the whole file into records (section|type|key|value|line) first, so extends can be loaded
  # before this file's values are applied on top
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    n=$(( n + 1 ))
    line=${raw%$'\r'}
    line=$(ly_trim "$line")
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^\[([a-z0-9-]+)([[:space:]]+([a-z0-9-]+))?\]$ ]]; then
      t=${BASH_REMATCH[1]}
      if [[ -z "${BASH_REMATCH[3]}" ]]; then
        case " layout frame photo $LY_BANDS " in
          *" $t "*) sec=$t; stype=$t ;;
          *) case " $LY_TYPES $LY_PLANNED " in
               *" $t "*) die "$file:$n: [$t] needs a name, e.g. [$t my-$t]" ;;
               *) die "$file:$n: unknown section [$t]" "Sections: [layout] [frame] [photo] [top] [bottom] [left] [right], items: [<type> <name>] with types $LY_TYPES" ;;
             esac ;;
        esac
      else
        case " $LY_TYPES " in
          *" $t "*) ;;
          *) case " $LY_PLANNED " in
               *" $t "*) die "$file:$n: [$t] items are planned but not available yet" ;;
               *) die "$file:$n: unknown item type '$t'" "Item types: $LY_TYPES" ;;
             esac ;;
        esac
        sec="i_${BASH_REMATCH[3]}"; stype=$t
      fi
      recs+=( "$sec|$stype|||$n" )
      continue
    fi
    if [[ "$line" =~ ^([a-z0-9-]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
      [[ -n "$sec" ]] || die "$file:$n: '$key' comes before any [section]"
      if [[ "$val" == \"* ]]; then
        # Quoted: up to the closing quote; only a comment may follow
        val=${val#\"}
        [[ "$val" == *\"* ]] || die "$file:$n: missing closing \" in the value of '$key'"
        t=${val#*\"}; val=${val%%\"*}
        t=$(ly_trim "$t")
        [[ -z "$t" || "$t" == \#* ]] || die "$file:$n: unexpected text after the closing \": $t"
      else
        # A comment is " # …": # between whitespace (or at the end), so colours like #F3F0E8 are values
        if [[ "$val" =~ ^(.*[^[:space:]])?[[:space:]]+#([[:space:]].*)?$ ]]; then val=${BASH_REMATCH[1]}; fi
        val=$(ly_trim "$val")
      fi
      case " $(ly_keys "$stype") " in
        *" $key "*) ;;
        *) die "$file:$n: unknown key '$key' in [$( [[ "$sec" == i_* ]] && echo "$stype ${sec#i_}" || echo "$sec")]" \
             "Keys there: $(ly_keys "$stype")" ;;
      esac
      [[ "$sec" == layout && "$key" == name && "$val" != "$name" ]] &&
        die "$file:$n: name = $val, but the file is $name.layout"
      [[ "$sec" == layout && "$key" == extends ]] && parent=$val
      recs+=( "$sec|$stype|$key|$val|$n" )
      continue
    fi
    die "$file:$n: expected [section] or key = value, got: $raw"
  done < "$file"

  # A layout may extend the one it replaces (your museum.layout extending the built-in museum)
  if [[ "$parent" == "$name" ]]; then ly_load "$parent" "$file"
  elif [[ -n "$parent" ]]; then ly_load "$parent"; fi

  local r rsec rtype rkey rval rn have
  for r in ${recs[@]+"${recs[@]}"}; do
    rsec=${r%%|*}; r=${r#*|}; rtype=${r%%|*}; r=${r#*|}; rkey=${r%%|*}; r=${r#*|}
    rn=${r##*|}; rval=${r%|*}
    if [[ -z "$rkey" ]]; then   # section header: register items, check the type matches the parent's
      if [[ "$rsec" == i_* ]]; then
        have=$(layout_get "$rsec" type)
        if [[ -z "$have" ]]; then
          LY_ITEMS="${LY_ITEMS:+$LY_ITEMS }${rsec#i_}"; printf -v "LYV_${rsec//-/_}__type" '%s' "$rtype"
        elif [[ "$have" != "$rtype" ]]; then
          die "$file:$rn: [$rtype ${rsec#i_}] is a $have item in the layout it extends"
        fi
      fi
      continue
    fi
    ly_vars "$rval" "$file:$rn"
    ly_set "$rsec" "$rkey" "$REPLY" "$file:$rn"
  done
  return 0
}

# The loaded layout as one tidy file: sections in a fixed order, items in order, keys as set
layout_dump() {
  local s k v list
  for s in layout frame photo $LY_BANDS $(for k in $LY_ITEMS; do echo "i_$k"; done); do
    list="LYK_${s//-/_}"; list=${!list-}
    if [[ "$s" == i_* ]]; then
      echo "[$(layout_get "$s" type) ${s#i_}]"
    else
      [[ -n "$list" || "$s" == layout ]] || continue
      echo "[$s]"
    fi
    [[ "$s" == layout ]] && echo "name = $LYV_layout__name"
    for k in $list; do
      [[ "$s" == layout && "$k" == name ]] && continue
      v=$(layout_get "$s" "$k")
      if [[ "$v" == " "* || "$v" == *" " ]]; then v="\"$v\""; fi
      echo "$k = $v"
    done
    echo
  done
}
