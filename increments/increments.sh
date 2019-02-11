#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

diffs=0
TARGET_DIFFS_DEFAULT="increments"
declare target_diffs
TARGET_MATCHES_DEFAULT="matches"
declare target_matches
remove_dupes=0
interactive_cleaning=1
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})
variants=${INCREMENTS_VARIANTS:-}
precedence=${INCREMENTS_PRECEDENCE:-}
declare tmp

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] search [search2 ..]
\nwhere OPTIONS can be:
  -t TARGET, --target TARGET:  search TARGET (path / archive)
  -v, --variants VARIANTS  : consider search variants given by
                             application of (sed) regexp
                             transformations in VARIANTS file
  -pp, --path-precedence  : pipe ('|') delimited list of partial
                            paths for matching on search results
                            in order to override the default order
                            of the ultimate set when desired
  -nd, --no-duplicates  : use only first instance of any duplicate
                          files matched
  -d, --diffs  : output incremental diffs of search matches
  -dd, --dump-diffs PATH  : write diffs to PATH (default: increments)
  -dm, --dump-matches PATH  : copy search matches to PATH
                              (default: matches)
  -ac, --auto-clean  : automatically clean dump targets (no prompt!)
\nenvironment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
"
}

fnCleanUp() {
  [ -n "$tmp" ] && [ -e "$tmp" ] && rm -rf "$tmp" 2>/dev/null 1>&2
}

fnClean() {
  declare target
  declare interactive
  declare files

  target="$1" && shift
  [ ! -e "$target" ] && echo "[error] invalid target '$target'" && return 1
  interactive=${1:-1}

  IFS=$'\n'; files=($(find "$target" -mindepth 1 -type "f")); IFS="$IFSORG"
  if [ ${#files[@]} -gt 0 ]; then
    res=1
    if [ $interactive -eq 1 ]; then
      echo -n "[user] target '$target' cleanup, purge ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")? [y/n]: "
      res=$(fnDecision)
    else
      echo "[info] target '$target' cleanup, purging ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")"
    fi
    [ $res -eq 1 ] && rm -rf "$target/*"
  fi
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

fnProcess() {

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

  # search
  declare -a files
  declare matches
  if [ ! -d "$target" ]; then
    # archive extraction
    globs=(); for s in "${search[@]}"; do globs=("${globs[@]}" "--wildcards" "*$s*"); done
    tmp=$(fnTempDir "$SCRIPTNAME")
    tar -C "$tmp" -x "${globs[@]}" -f "$target" 2>/dev/null
    res=$?
    if [ $res -ne 0 ]; then
      [ $res -eq 2 ] && \
        echo "[info] ignoring GNU tar 'not found in archive' 'errors'" 1>&2 || return $res
    fi
    target=$tmp
  fi
  # directory search
  rx=""; for s in "${search[@]}"; do rx+="\|$s"; done; rx="^.*/?\(${rx:2}\)$"
  matches="$(find "$target" -mindepth 1 -iregex "$rx")"
  IFS=$'\n'; files=($(echo -e "$matches")); IFS="$IFSORG"
  [ $DEBUG -ge 1 ] && echo "[debug] searched target '$target' for '${search[@]}', found ${#files[@]} file(s)" 1>&2

  [ ${#files[@]} -eq 0 ] && echo "[info] no files found" && return 1

  # dump matches
  if [ -n "$target_matches" ]; then
    [ ! -d "$target_matches" ] && mkdir -p "$target_matches"
    fnClean "$target_matches" $interactive_cleaning
    for f in ${files[@]}; do cp -a --parents "$f" "$target_matches/"; done
    echo "[info] dumped ${#files[@]} matches to '$target_matches'" 1>&2
  fi

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
  [ $DEBUG -ge 2 ] && echo -e "[debug] timestamp sorted table\n$sorted"

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
        [ $res -ne 0 ] && return $res
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
    [ $DEBUG -ge 2 ] && echo -e "[debug] duplicate tested table\n$compared_dupe" 1>&2
    sorted="$(echo -e "$compared_dupe" | sort -t$'\t' -k1 | sed '/\t1/d;s/\t0$//')"
    [ $DEBUG -ge 2 ] && echo -e "[debug] timestamp sorted duplicate free table\n$sorted" 1>&2
  fi

  matches=$(echo -e "$sorted" | wc -l)
  echo "[info] matched ${matches}$([ ${#files[@]} -ne ${#sorted[@]} ] && echo " unique") file$([ $matches -ne 1 ] && echo "s")" 1>&2

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
    [ $DEBUG -ge 2 ] && echo -e "[debug] timestamp sorted precedence sets keyed table\n$s"
    sorted="$(echo "$s" | sort | sed 's/^_[0-9]\+_\t//')"
    [ $DEBUG -ge 2 ] && echo -e "[debug] timestamp sorted precedence table\n$sorted"
  fi

  # switch to array items
  IFS=$'\n'; sorted=($(echo -e "$sorted")); IFS="$IFSORG"

  # diffs
  if [[ $diffs -eq 1 || -n "$target_diffs" ]]; then
    diff_bin="$(which diff)"
    if [ -z "$diff_bin" ]; then
      echo "[error] no 'diff' binary found in your PATH" 1>&2
    else
      [[ -n "$target_diffs" && ! -d "$target_diffs" ]] && mkdir -p "$target_diffs"
      fnClean "$target_diffs" $interactive_cleaning
      last="/dev/null"
      for r in "${sorted[@]}"; do
        [ $DEBUG -ge 3 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
        IFS=$'\t'; fields=($r); IFS="$IFSORG"
        ts=${fields[0]}
        sz=${fields[1]}
        f="${fields[2]}"
        diff_bin_args=("-u" "$last" "$f")
        [ $DEBUG -ge 2 ] && echo "[debug] diff '$last <-> $f'"
        if [[ $diffs -eq 1 && -n "$target_diffs" ]]; then
          $diff_bin "${diff_bin_args[@]}" | tee "$target_diffs/$ts.diff"
        elif [ $diffs -eq 1 ]; then
          $diff_bin "${diff_bin_args[@]}"
        else
          $diff_bin "${diff_bin_args[@]}" > "$target_diffs/$ts.diff"
        fi
        last="$f"
      done
      [ -n "$target_diffs" ] && \
        echo "[info] dumped ${#sorted[@]} diffs to '$target_diffs'" 1>&2
    fi
  fi

  # list
  echo "[info] file list:"
  date_format="%Y%b%d %H:%M:%S %z"
  field_date=0; field_size=1; field_path=2
  field_widths=(25 $(($maxlen_size+1)) $(($maxlen_path+1)))
  field_order=(2 1 0)
  # header
  printf "%s%$((${field_widths[$field_path]}-4))s%$((${field_widths[$field_size]}-4))s%s%$((${field_widths[$field_date]}-4))s%s\n" "path" " " " " "size" " " "date"
  # rows
  for r in "${sorted[@]}"; do
    [ $DEBUG -ge 3 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
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

}

# option parsing
while [ -n "$1" ]; do
  s="$(echo "$1" | sed -n 's/^-*//gp')"
  case "$s" in
    "h"|"help") help && exit ;;
    "t"|"target") shift; target="$1" ;;
    "v"|"variants") shift; variants="$1" ;;
    "pp"|"path-precedence") shift; precedence="$1" ;;
    "nd"|"no-duplicates") remove_dupes=1 ;;
    "d"|"diffs") diffs=1 ;;
    "dd") target_diffs="$TARGET_DIFFS_DEFAULT" ;;
    "dump-diffs") shift; target_diffs="$1" ;;
    "dm") target_matches="$TARGET_MATCHES_DEFAULT" ;;
    "dump-matches") shift; target_matches="$1" ;;
    "ac"|"auto-clean") interactive_cleaning=0 ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done
[ $DEBUG -ge 1 ] && echo "[debug] search: [${search[@]}], target: `basename $target`, diffs: $diffs: diffs target: $target_diffs, matches target: $target_matches" 1>&2

# option validation
## search
[ ${#search[@]} -eq 0 ] && help && echo "[error] no search items specified" && exit 1
## target
if [ ! -e "$target" ]; then
  echo "[error] invalid search target set '$target'. exiting!" && exit 1
else
  if [ -f "$target" ]; then
    # ensure it's a supported file
    type="$(file --brief --mime-type "$target")"
    type_required="application/x-tar"
    [ "x$type" != "x$type_required" ] &&
      echo "[error] target file type '$type' unsupported, expected '$type_expected' archive" && exit
  fi
fi

# run
fnProcess

# clean up
fnCleanUp
