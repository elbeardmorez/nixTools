#!/bin/sh

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

# compatibility
if [ -n "$ZSH_VERSION" ]; then
  setopt KSH_ARRAYS
fi

mode="list"
dump="increments"
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})
variants=${INCREMENTS_VARIANTS:-}

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [MODE] [OPTIONS] search [search2 ..]
\nwhere MODE can be:
  list  : list search matches in incremental order
  diffs  : create a set of diffs from matches
    where OPTIONS can be:
      -d, --dump TARGET  : target path for diffs (default: increments)
where OPTIONS can be:
  -t, --target TARGET:  search path
  -v, --variants VARIANTS  : consider search variants given by
                             application of (sed) regexp
                             transformations in VARIANTS file
\nenvironment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
"
}

while [ -n "$1" ]; do
  s="$(echo "$1" | sed -n 's/^-*//gp')"
  case "$s" in
    "h"|"help") help && exit ;;
    "list"|"diffs") mode="$s" ;;
    "t"|"target") shift; target="$1" ;;
    "d"|"dump") shift; dump="$1" ;;
    "v"|"variants") shift; variants="$1" ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done

[ $DEBUG -gt 0 ] && echo "[debug] mode: $mode, search: [${search[@]}], target: `basename $target`, dump: $dump, ]" 1>&2

[ ${#search[@]} -eq 0 ] && help && echo "[error] no search items specified" &&  exit 1
[ ! -d "$target" ] && echo "[error] invalid search target set '$target'. exiting!" && exit 1

if [ -n "$variants" ]; then
  if [ ! -f "$variants" ]; then
    echo "[error] invalid variants file set '$variants'. ignoring!"
  else
    declare -a search2
    search2=""
    while read line; do
      for s in "${search[@]}"; do
        search2+="$s\n"
        v=$(echo "$s" | sed "s$line")
        [ -n "${v}" ] && search2+="$v\n"
      done
    done < $variants
    # unique only
    IFS=$'\n'; search=($(echo -e "$search2" | sort -u)); IFS="$IFSORG"
  fi
fi

# search regexp
rx=""
for s in "${search[@]}"; do rx+="\|$s"; done
rx="^.*/?\(${rx:2}\)$"

# search
IFS=$'\n'; files=(`find "$target" -iregex "$rx"`); IFS="$IFSORG"
[ $DEBUG -gt 0 ] && echo "[debug] searched target '$target' for '${search[@]}', found ${#files[@]} file(s)" 1>&2

[ ${#files[@]} -eq 0 ] && echo "[info] no files found" && exit
maxlen_path=4
maxlen_size=4
s=""
for f in ${files[@]}; do
  [ ${#f} -gt $maxlen_path ] && maxlen_path=${#f}
  i=`stat -L "$f"`
  ts=`echo -e "$i" | grep "Modify" | cut -d' ' -f2- | xargs -I '{}' date -d '{}' '+%s'`
  sz=`echo -e "$i" | sed -n 's/.*Size: \([0-9]\+\).*/\1/p'`
  [ ${#sz} -gt $maxlen_size ] && maxlen_size=${#sz}
  s="$s\n$ts\t$sz\t$f"
done
s="${s:2}"

IFS=$'\n'; sorted=(`echo -e "$s" | sort -t$'\t' -k1`); IFS="$IFSORG"

case "$mode" in
  "list")
    echo "[info] matched ${#files[@]} files" 1>&2
    date_format="%Y%b%d %H:%M:%S %z"
    field_date=0; field_size=1; field_path=2
    field_widths=(25 $(($maxlen_size+1)) $(($maxlen_path+1)))
    field_order=(2 1 0)
    # header
    printf "\n%s%$((${field_widths[$field_path]}-4))s%$((${field_widths[$field_size]}-4))s%s%$((${field_widths[$field_date]}-4))s%s\n" "path" " " " " "size" " " "date"
    # rows
    for r in "${sorted[@]}"; do
      [ $DEBUG -gt 2 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
      IFS=$'\t'; fields=($r); IFS="$IFSORG"
      for l in ${field_order[@]}; do
        f="${fields[$l]}"
        if [ $l -eq $field_path ]; then
          # align left
          printf "%s%$((${field_widths[$l]}-${#f}))s" "$f" " "
        elif [ $l -eq $field_date ]; then
          d=$(date --date "@$f" "+$date_format")
          printf "%${field_widths[$l]}s" "$d"
        else
          printf "%${field_widths[$l]}s" "$f"
        fi
      done
      printf '\n'
    done
    ;;
  "diffs")
    [ ! -d "$dump" ] && mkdir -p "$dump"
    last="/dev/null"
    for r in "${sorted[@]}"; do
      [ $DEBUG -gt 2 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
      IFS=$'\t'; fields=($r); IFS="$IFSORG"
      ts=${fields[0]}
      sz=${fields[1]}
      f="${fields[2]}"
      [ $DEBUG -gt 1 ] && echo "[debug] diff '$last <-> $f'"
      diff -u "$last" "$f" > "$dump/$ts.diff"
      last="$f"
    done
    echo "[info] dumped ${#sorted[@]} diffs to '$dump'" 1>&2
    ;;
esac
