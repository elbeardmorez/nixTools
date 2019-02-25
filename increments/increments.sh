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
declare -a targets
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})
variants=${INCREMENTS_VARIANTS:-}
precedence=${INCREMENTS_PRECEDENCE:-}
declare tmp
diff_format_git=0
diff_format_paths=0
GIT_DIFF_HEADER=\
"From fedcba10987654321012345678910abcdef Mon Sep 17 00:00:00 2001\n"\
"From: @NAME <@EMAIL>\nDate: @DATE\nSubject: @SUBJECT\n\n---\n"
GIT_DIFF_FOOTER="--\n2.20.1"
GIT_DIFF_DT_FORMAT="%a, %d %b %Y %T %z"  # e.g. Mon, 1 Jan 1970 00:00:00 +0000
diff_numeric_prefixes=0
GIT_DIFF_SUBJECT=${GIT_DIFF_SUBJECT:-"[diff]"}
DIFF_TARGET_BASE_PATH=${DIFF_TARGET_BASE_PATH:-""}
DIFF_TARGET_FILE=${DIFF_TARGET_FILE:-""}

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] search [search2 ..]
\nwhere OPTIONS can be:
  -t TARGETS, --target TARGETS  : pipe ('|') delimited list of search
                                  targets (paths / tar archives)
  -v VARIANTS, --variants VARIANTS  : consider search variants given
                                      by application of (sed) regexp
                                      transformations in VARIANTS file
  -pp PATHS, --path-precedence PATHS : pipe ('|') delimited list of
                                       partial paths for matching on
                                       search results in order to
                                       override the default order of
                                       the ultimate set when desired
  -nd, --no-duplicates  : use only first instance of any duplicate
                          files matched
  -d, --diffs  : output incremental diffs of search matches
  -dd, --dump-diffs PATH  : write diffs to PATH (default: increments)
  -dm, --dump-matches PATH  : copy search matches to PATH
                              (default: matches)
  -ac, --auto-clean  : automatically clean dump targets (no prompt!)
  -dfp, --diff-format-paths  : format paths in any incremental diffs
                               generated to the standard
                               'a[/PATH]/FILE' 'b[/PATH]/FILE pair.
                               by default, PATH is stripped, and FILE
                               is set to the latter of the diff pair's
                               names. see environment variable below
                               for overrides
  -dfg, --diff-format-git  : add git mailinfo compatible headers to
                             diff files
  -dnp, --diff-numeric-prefixes  : prefix diff number to file name
\nenvironment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
  DIFF_TARGET_BASE_PATH  : base path of file to be use in any
                           incremental diffs generated e.g.
                           'a/GIT_DIFF_BASE_PATH/FILE'
  DIFF_TARGET_FILE  : file name override for any incremental diffs
                      generated. e.g. 'b/DIFF_TARGET_FILE'
  GIT_DIFF_SUBJECT  : subject line for any incremental diffs generated
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
    res="y"
    if [ $interactive -eq 1 ]; then
      echo -n "[user] target '$target' cleanup, purge ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")? [y/n]: "
      res=$(fnDecision)
    else
      echo "[info] target '$target' cleanup, purging ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")"
    fi
    [ "x$res" == "xy" ] && rm -r "$target/"*
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
  declare files
  declare matches
  for target in "${targets[@]}"; do
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
    files="$(find "$target" -mindepth 1 -iregex "$rx")"
    matches+="\n$files"
    count=$(echo -e "$files" | wc -l)
    [ $DEBUG -ge 1 ] && echo "[debug] searched target '$target' for '${search[@]}, matched $count file$([ $count -ne 1 ] && echo "s")'" 1>&2
  done
  matches="${matches:2}"
  IFS=$'\n'; files=($(echo -e "$matches")); IFS="$IFSORG"
  [ ${#files[@]} -eq 0 ] && echo "[info] no files found" && return 1
  echo "[info] matched ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")" 1>&2

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
    sorted="$(echo -e "$compared_dupe" | sort -t$'\t' -k1 | sed '/\t1$/d;s/\t0$//')"
    [ $DEBUG -ge 2 ] && echo -e "[debug] timestamp sorted duplicate free table\n$sorted" 1>&2
  fi

  matches=$(echo -e "$sorted" | wc -l)
  [ ${#files[@]} -ne ${#sorted[@]} ] && echo "[info] ${matches} unique file$([ $matches -ne 1 ] && echo "s")" 1>&2

  # precedence
  if [ -n "$precedence" ]; then
    IFS=$'|'; precedence_sets_searches=($(echo "$precedence")); IFS="$IFSORG"
    s="$sorted"
    l=0
    for pss in "${precedence_sets_searches[@]}"; do
      s="$(echo -e "$s" | sed '/^_[0-9]\+_/{b;};s/^\(.*'"$(fn_rx_escape "sed" "$pss")"'[^\t]*\)$/_'$l'_\t\1/')"
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
      git_bin="$(which git)"
      name=""
      email=""
      if [ -n "$git_bin" ]; then
        name="$($git_bin config --get user.name)"
        email="$($git_bin config --get user.email)"
      fi
      last="/dev/null"
      l=1
      for r in "${sorted[@]}"; do
        [ $DEBUG -ge 3 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
        IFS=$'\t'; fields=($r); IFS="$IFSORG"
        ts=${fields[0]}
        sz=${fields[1]}
        f="${fields[2]}"
        diff_bin_args=("-u" "$last" "$f")
        diff_pathfile="$target_diffs/$ts.diff"
        [ $diff_numeric_prefixes -eq 1 ] &&\
          diff_pathfile="$(printf "%s/%04d_%s" "$target_diffs" $l "$ts.diff")"
        [ $DEBUG -ge 2 ] && echo "[debug] diff '$last <-> $f'"
        if [[ $diffs -eq 1 && -n "$target_diffs" ]]; then
          $diff_bin "${diff_bin_args[@]}" | tee "$diff_pathfile"
        elif [ $diffs -eq 1 ]; then
          $diff_bin "${diff_bin_args[@]}"
        else
          $diff_bin "${diff_bin_args[@]}" > "$diff_pathfile"
        fi
        if [[ $diff_format_git -eq 1 && -e $diff_pathfile && -e "$diff_pathfile" ]]; then
          # add header / footer
          diff_header="$GIT_DIFF_HEADER"
          diff_footer="$GIT_DIFF_FOOTER"
          diff_header="$(echo "$diff_header" | sed 's/@DATE/'"$(date -d "@$ts" "+$GIT_DIFF_DT_FORMAT")"'/')"
          [ -n "$name" ] && \
            diff_header="$(echo "$diff_header" | sed 's/@NAME/'"$name"'/')"
          [ -n "$email" ] && \
            diff_header="$(echo "$diff_header" | sed 's/@EMAIL/'"$email"'/')"
          diff_header="$(echo "$diff_header" | sed 's/@SUBJECT/'"$GIT_DIFF_SUBJECT"'/')"
          sed -i '1s/^/'"$diff_header"'\n/' "$diff_pathfile"
          sed -i '$s/$/\n'"$diff_footer"'\n/' "$diff_pathfile"
        fi
        if [[ $diff_format_paths -eq 1 && -e $diff_pathfile && -e "$diff_pathfile" ]]; then
          # modify target paths
          target_base_path="$DIFF_TARGET_BASE_PATH"
          [ -n "$target_base_path" ] && \
            target_base_path="$(echo "$target_base_path" | sed 's/\/*$//g')\/"
          target_file="$DIFF_TARGET_FILE"
          sed -i '/^-\{3\}[ \t]*./{/\/dev\/null/b;s/\([+-]\{3\}[ \t]*\).*\/\([^\t]*\)\(.*\)$/\1a\/'"${target_base_path}${target_file:-\2}"'\3/}' "$diff_pathfile"
          sed -i '/^+\{3\}[ \t]*./{/\/dev\/null/b;s/\([+-]\{3\}[ \t]*\).*\/\([^\t]*\)\(.*\)$/\1b\/'"${target_base_path}${target_file:-\2}"'\3/}' "$diff_pathfile"
        fi
        last="$f"
        l=$(($l+1))
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
    "dfg"|"diff-format-git") diff_format_git=1 ;;
    "dfp"|"diff-format-paths") diff_format_paths=1 ;;
    "dnp"|"diff-numeric-prefixes") diff_numeric_prefixes=1 ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done
[ $DEBUG -ge 1 ] && echo "[debug] search: [${search[@]}], target: `basename $target`, diffs: $diffs: diffs target: $target_diffs, matches target: $target_matches" 1>&2

# option validation
## search
[ ${#search[@]} -eq 0 ] && help && echo "[error] no search items specified" && exit 1
## target
IFS=$'|'; targets=($(echo "$target")); IFS="$IFSORG"
for target in "${targets[@]}"; do
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
done

# run
fnProcess

# clean up
fnCleanUp
