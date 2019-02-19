#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

PATHS=(~/documents)
FILE_RESULTS=""
SEARCH_TARGETS="$HOME/.search"
SEARCH=""
search_targets=0
interactive=0

help() {
  echo -e "SYNTAX '$SCRIPTNAME [OPTIONS] SEARCH
\nwhere 'OPTIONS' can be\n
  -h, --help  : this help information
  -i, --interactive  : enable verification prompt for each match
                       (default: off / auto-accept)
  -t, --target TARGETS  : file containing search targets, one per line
                          (default: ~/.search)
  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line
\nand 'SEARCH' is  : a (partial) file name to search for in the list of
                     predefined search paths*
\n*predefined paths are currently: $(for p in "${PATHS[@]}"; do echo -e "\n$p"; done)
"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/[ ]*-*//g')"
  case "$arg" in
    "h"|"help") help && exit ;;
    "i"|"interactive") interactive=1 ;;
    "t") search_targets=1 ;;
    "target") search_targets=1 && shift && SEARCH_TARGETS="$1" ;;
    "r"|"results") shift && FILE_RESULTS="$1" ;;
    *) [ -n "$SEARCH" ] && help && echo "[error] unknown arg '$arg'"; SEARCH="$1" ;;
  esac
  shift
done

# option verification
if [ -n "$FILE_RESULTS" ]; then
  [ -d "$(dirname "$FILE_RESULTS")" ] || mkdir -p "$(dirname "$FILE_RESULTS")"
fi
if [ $search_targets -eq 1 ]; then
  [ ! -f "$SEARCH_TARGETS" ] && echo "[error] invalid search targets file '$SEARCH_TARGETS'" && exit 1
fi

declare files
declare -a results

if [ -f $SEARCH ]; then
  # prioritise local files
  results[${#results[@]}]="$SEARCH"
elif [[ ! "x$(dirname $SEARCH)" == "x." || "x${SEARCH:0:1}" == "x." ]]; then
  # create file
  if [ $interactive -eq 1 ]; then
    # new file. offer creation
    echo -n "[user] file '$SEARCH' does not exist, create it? [y/n]: " 1>&2
    fnDecision >/dev/null || exit
    # ensure path
    [ -d "$(dirname $SEARCH)" ] || mkdir -p "$(dirname $SEARCH)"
    touch "$SEARCH"
    results[${#results[@]}]="$SEARCH"
  fi
else
  # use search paths
  paths="${PATHS[@]}"
  if [ $search_targets -eq 1 ]; then
    IFS=$'\n'; paths=($(cat "$SEARCH_TARGETS")); IFS="$IFSORG"
  fi
  for p in "${paths[@]}"; do
    p="$(eval "echo $p")"  # resolve target
    if [ ! -e "$p" ]; then
      echo "[info] path '$p' invalid or it no longer exists, ignoring" 1>&2
    else
      IFS=$'\n'; files2=($(find $p -name "$SEARCH" \( -type f -o -type l \))); IFS="$IFSORG"
      for file in "${files2[@]}"; do files[${#files[@]}]="$file"; done
    fi
  done

  for file in "${files[@]}"; do
    if [[ ${#files[@]} == 1 || $interactive -eq 0 ]]; then
      results[${#results[@]}]="$file"
    else
      result=""
      echo -n "[user] search match, use file '$file'? [y/n/c]: " 1>&2
      res="$(fnDecision "y|n|c")"
      [ "x$res" == "xc" ] && exit  # !break, no partial results
      [ "x$res" == "xn" ] && continue
      results[${#results[@]}]="$file"
    fi
  done
fi

if [ ${#results[@]} -gt 0 ]; then
  s=""
  for f in "${results[@]}"; do s+="\n$f"; done
  results="${s:2}"
  [ -n "$FILE_RESULTS" ] && echo -e "$results" >> "$FILE_RESULTS"
  echo -e "$results"
else
  [ ${#files[@]} -eq 0 ] &&\
    echo "[info] no matches for search '$SEARCH'" 1>&2
fi
