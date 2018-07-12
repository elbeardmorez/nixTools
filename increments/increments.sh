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
  [ $DEBUG -gt 1 ] && echo "[debug] searched target for '$s', found ${files2[@]} file(s)" 1>&2
  files=("${files[@]}" "${files2[@]}")
done

for f in "${files[@]}"; do
  echo "$f"
done
