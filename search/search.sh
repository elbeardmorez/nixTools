#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

paths=(~/documents)
file_results=""
search_targets="$HOME/.nixTools/$SCRIPTNAME"
search=""
search_targets=0
interactive=0
verbose=0

help() {
  echo -e "SYNTAX '$SCRIPTNAME [OPTIONS] SEARCH
\nwhere 'OPTIONS' can be\n
  -h, --help  : this help information
  -i, --interactive  : enable verification prompt for each match
                       (default: off / auto-accept)
  -t TARGET, --target TARGETS  : override path to file containing
                                 search targets, one per line
                                 (default: ~/.search)
  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line
  -v, --verbose                : output additional info
\nand 'SEARCH' is  : a (partial) file name to search for in the list of
                     predefined search paths*
\n*predefined paths are currently: $(for p in "${paths[@]}"; do echo -e "\n$p"; done)
"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/[ ]*-*//g')"
  case "$arg" in
    "h"|"help") help && exit ;;
    "i"|"interactive") interactive=1 ;;
    "t"|"target") search_targets=1 && shift && search_targets="$1" ;;
    "r"|"results") shift && file_results="$1" ;;
    "v"|"verbose") verbose=1 ;;
    *) [ -n "$search" ] && help && echo "[error] unknown arg '$arg'"; search="$1" ;;
  esac
  shift
done

# option verification
if [ -n "$file_results" ]; then
  [ -d "$(dirname "$file_results")" ] || mkdir -p "$(dirname "$file_results")"
fi
if [ $search_targets -eq 1 ]; then
  [ ! -f "$search_targets" ] && echo "[error] invalid search targets file '$search_targets'" && exit 1
fi

declare -a files
declare -a files2
declare -a results
declare -A map

if [ -f "$search" ]; then
  # prioritise local files
  results[${#results[@]}]="$search"
elif [[ ! "x$(dirname "$search")" == "x." || "x${search:0:1}" == "x." ]]; then
  # create file
  if [ $interactive -eq 1 ]; then
    # new file. offer creation
    fn_decision "[user] file '$search' does not exist, create it?" >/dev/null || exit
    # ensure path
    [ -d "$(dirname "$search")" ] || mkdir -p "$(dirname "$search")"
    touch "$search"
    results[${#results[@]}]="$search"
  fi
else
  # use search paths
  [ -f "$search_targets" ] && IFS=$'\n'; paths=($(cat "$search_targets")); IFS="$IFSORG" || paths=("${paths[@]}")
  for p in "${paths[@]}"; do
    p="$(eval "echo $p")"  # resolve target
    if [ -e "$p" ]; then
      IFS=$'\n'; files2=($(find $p -name "$search" \( -type f -o -type l \))); IFS="$IFSORG"
      for file in "${files2[@]}"; do files[${#files[@]}]="$file"; done
    elif [ $verbose -eq 1 ]; then
      echo "[info] path '$p' invalid or it no longer exists, ignoring" 1>&2
    fi
  done

  for file in "${files[@]}"; do
    [ -n "${map["$file"]}" ] && continue  # no dupes
    if [[ ${#files[@]} == 1 || $interactive -eq 0 ]]; then
      results[${#results[@]}]="$file"
      map["$file"]=1
    else
      result=""
      res="$(fn_decision "[user] search match, use file '$file'?" "ync")"
      [ "x$res" == "xc" ] && exit  # !break, no partial results
      [ "x$res" == "xn" ] && continue
      results[${#results[@]}]="$file"
      map["$file"]=1
    fi
  done
fi

if [ ${#results[@]} -gt 0 ]; then
  s=""
  for f in "${results[@]}"; do s+="\n$f"; done
  results="${s:2}"
  [ -n "$file_results" ] && echo -e "$results" >> "$file_results"
  echo -e "$results"
else
  [ ${#files[@]} -eq 0 ] &&\
    echo "[info] no matches for search '$search'" 1>&2
fi
