#!/bin/bash

IFSORG="$IFS"
DEBUG=${DEBUG:-0}

mode="list"
dump="incremental"
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})

mode="list"
while [ -n "$1" ]; do
  s="$(echo "$1" | sed -n 's/^-*//gp')"
  case "$s" in
    "list"|"diffs") mode="$s" ;;
    "t"|"target") shift; target="$1" ;;
    "d"|"dump") shift; dump="$1" ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done

[ $DEBUG -gt 0 ] && echo "[debug] mode: $mode, search: [${search[@]}], target: `basename $target`, dump: $dump, ]" 1>&2

[[ $target == "" || ! -d "$target" ]] && echo "[error] invalid search target set '$target'. exiting!" && exit 1

files=()
for s in "${search[@]}"; do
  IFS=$'\n'; files2=(`find "$target" -iname "$s"`); IFS="$IFSORG"
  [ $DEBUG -gt 1 ] && echo "[debug] searched target for '$s', found ${#files2[@]} file(s)" 1>&2
  files=("${files[@]}" "${files2[@]}")
done
[ $DEBUG -gt 0 ] && echo "[debug] searched target '$target', found ${#files[@]} file(s)" 1>&2

[ ${#files[@]} -eq 0 ] && echo "no files found" && exit

s=""
for f in ${files[@]}; do
  i=`stat -L "$f"`
  ts=`echo -e "$i" | grep "Modify" | cut -d' ' -f2- | xargs -I '{}' date -d '{}' '+%s'`
  sz=`echo -e "$i" | sed -n 's/.*Size: \([0-9]\+\).*/\1/p'`
  s="$s\n$ts\t$sz\t$f"
done
s="${s:2}"

case "$mode" in
  "list")
    echo -e "$s" | sort -t$'\t' -k1
    ;;
  "diffs")
    [ ! -d "$dump" ] && mkdir "$dump"
    IFS=$'\n'; sorted=(`echo -e "$s" | sort -t$'\t' -k1`); IFS="$IFSORG"
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
    ;;
esac
