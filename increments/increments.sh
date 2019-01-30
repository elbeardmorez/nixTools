#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

mode="list"
dump="increments"
remove_dupes=0
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})
variants=${INCREMENTS_VARIANTS:-}
precedence=${INCREMENTS_PRECEDENCE:-}

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
  -pp, --path-precedence  : pipe ('|') delimited list of partial
                            paths for matching on search results
                            in order to override the default order
                            of the ultimate set when desired
  -nd, --no-duplicates  : use only first instance of any duplicate
                          files matched
\nenvironment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
"
}

fnFilesCompare() {
  [ $DEBUG -ge 5 ] && echo "[debug | fnFilesCompare]" 1>&2
  [ $# -lt 2 ] && echo "[error] not enough args" 1>&2 && return 1
  declare base
  declare md5base
  declare md5compare
  declare res
  base="$1" && shift
  [ ! -f "$base" ] && echo "[error] invalid file '$base'" 1>&2 && return 1
  md5base="$(md5sum "$base" | cut -d' ' -f1)"
  res=""
  while [ -n "$1" ]; do
    compare="$1"
    [ ! -f "$base" ] && echo "[error] invalid file '$compare'" 1>&2 && return 1
    md5compare="$(md5sum "$compare" | cut -d' ' -f1)"
    res+="\n$compare\t$([ "x$md5base" == "x$md5compare" ] && echo 1 || echo 0)"
    shift
  done
  echo -e "${res:2}"
}

while [ -n "$1" ]; do
  s="$(echo "$1" | sed -n 's/^-*//gp')"
  case "$s" in
    "h"|"help") help && exit ;;
    "list"|"diffs") mode="$s" ;;
    "t"|"target") shift; target="$1" ;;
    "d"|"dump") shift; dump="$1" ;;
    "v"|"variants") shift; variants="$1" ;;
    "pp"|"path-precedence") shift; precedence="$1" ;;
    "nd"|"no-duplicates") shift; remove_dupes=1 ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done

[ $DEBUG -gt 0 ] && echo "[debug] mode: $mode, search: [${search[@]}], target: `basename $target`, dump: $dump" 1>&2

[ ${#search[@]} -eq 0 ] && help && echo "[error] no search items specified" &&  exit 1
[ ! -d "$target" ] && echo "[error] invalid search target set '$target'. exiting!" && exit 1

if [ -n "$variants" ]; then
  if [ ! -f "$variants" ]; then
    echo "[error] invalid variants file set '$variants'. ignoring!"
  else
    declare -a search2
    search2=""
    IFS=$'\n'; transforms=($(cat "$variants")); IFS="$IFSORG"
    for transform in "${transforms[@]}"; do
      for s in "${search[@]}"; do
        search2+="$s\n"
        v=$(echo "$s" | sed 's'"$transform")
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
sorted="$(echo -e "$s" | sort -t$'\t' -k1)"
[ $DEBUG -gt 1 ] && echo -e "[debug] timestamp sorted table\n$sorted"

# duplicates
if [ $remove_dupes -eq 1 ]; then
  IFS=$'\n'; sorted_size=($(echo -e "$sorted" | sort -t$'\t' -k2)); IFS="$IFSORG" # sort by size
  l1=0
  compared_dupe=""
  while [ $l1 -lt ${#sorted_size[@]} ]; do
    sz="$(echo "${sorted_size[$l1]}" | cut -d$'\t' -f2)"
    f="$(echo "${sorted_size[$l1]}" | cut -d$'\t' -f3)"
    compared_dupe+="\n${sorted_size[$l1]}\t0"  # unique or first
    l1=$(($l1+1))
    l2=0
    s=()
    while [[ $(($l1+$l2)) -lt ${#sorted_size[@]} && \
             $sz -eq $(echo "${sorted_size[$(($l1+$l2))]}" | cut -d$'\t' -f2) ]]; do
      # collect any files with same size as first/base, yet to be deemed 'dupe'
      f2="$(echo "${sorted_size[$(($l1+$l2))]}" | cut -d$'\t' -f3)"
      dupe="$(echo "${sorted_size[$(($l1+$l2))]}" | cut -d$'\t' -f4)"
      [ -z "$dupe" ] && s[${#s[@]}]="$f2"
      l2=$(($l2+1))
    done
    if [ ${#s[@]} -gt 0 ]; then
      # make comparison
      compared="$(fnFilesCompare "$f" "${s[@]}")"
      res=$?
      [ $res -ne 0 ] && exit $res
      # create merged data subset for sort
      IFS=$'\n'; compared=($(echo -e "$compared")); IFS="$IFSORG"
      s=""
      for l3 in $(seq 0 1 $((l2-1))); do
        s2="${sorted_size[$(($l1+$l3))]}"
        c="${compared[$l3]}"
        s+="\n$([ ${c#*$'\t'} -eq 1 ] && echo "${s2%$'\t'*%}\t1" || echo "${sorted_size[$(($l1+$l3))]}")"
      done
      # update set / replace subset with any dupes first
      IFS=$'\n'; compared=($(echo -e "$s" | sort -t$'\t' -k4 -r)); IFS="$IFSORG"
      dupes_count=0
      for l3 in $(seq 0 1 $((l2-1))); do
        sorted_size[$(($l1+$l3))]="${compared[$l3]}"
        if [ -n "$(echo "${compared[$l3]}" | cut -d$'\t' -f4)" ]; then
          compared_dupe+="\n${compared[$l3]}"  # dupe
          dupes_count=$(($dupes_count+1))
        fi
      done
      # move index beyond dupes for next base
      l1=$(($l1+$dupes_count))
    fi
  done
  compared_dupe="${compared_dupe:2}"
  [ $DEBUG -gt 1 ] && echo -e "[debug] duplicate tested table\n$compared_dupe" 1>&2
  sorted="$(echo -e "$compared_dupe" | sort -t$'\t' -k1 | sed '/\t1/d;s/\t0$//')"
  [ $DEBUG -gt 1 ] && echo -e "[debug] timestamp sorted duplicate free table\n$sorted" 1>&2
fi

# precedence
if [ -n "$precedence" ]; then
  IFS=$'|'; precedence_sets_searches=($(echo "$precedence")); IFS="$IFSORG"
  s="$sorted"
  l=0
  for pss in "${precedence_sets_searches[@]}"; do
    s="$(echo -e "$s" | sed '/^_[0-9]\+_/{b;};s/^\(.*'"$(fnRegexp "$pss")"'[^\t]*\)$/_'$l'_\t\1/')"
    l=$(($l+1))
  done
  s="$(echo -e "$s" | sed '/^_[0-9]\+_/{b;};s/^\(.*\)$/_'$l'_\t\1/')"
  [ $DEBUG -gt 1 ] && echo -e "[debug] timestamp sorted precedence sets keyed table\n$s"
  sorted="$(echo "$s" | sort | sed 's/^_[0-9]\+_\t//')"
  [ $DEBUG -gt 1 ] && echo -e "[debug] timestamp sorted precedence table\n$sorted"
fi

IFS=$'\n'; sorted=($(echo -e "$sorted")); IFS="$IFSORG"
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
