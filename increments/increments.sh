#!/bin/bash

IFSORG="$IFS"
DEBUG=${DEBUG:-0}

target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})

args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"
  case "$arg" in
    "-n"|"--name") i=$[$i+1] && name="${args[$i]}" ;;
    "-t"|"--target") i=$[$i+1] && target="${args[$i]}" ;;
    *) search[${#search[@]}]="$arg" ;;
  esac
  i=$[$i+1]  
done

[ $DEBUG -gt 0 ] && echo "[debug] target: $target, search: [${search[@]}]" 1>&2

[[ $target == "" || ! -d "$target" ]] && echo "search target not set, exiting!" && exit 1

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
  ts=`stat "$f" | grep Modify | cut -d' ' -f2- | xargs -I '{}' date -d '{}' '+%s'`
  s="$s\n$ts\t$f"
done

IFS=$'\n'; sorted=(`echo -e "$s" | sort -t$'\t' -k1`); IFS="$IFSORG"
for r in "${sorted[@]}"; do
  IFS=$'\t'; fields=($r); IFS="$IFSORG"
  dt=${fields[0]}
  f="${fields[1]}"
  echo "$f"
done
