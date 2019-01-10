#!/bin/sh

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
