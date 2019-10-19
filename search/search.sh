#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

rc="$HOME/.nixTools/$SCRIPTNAME"

declare search_types; search_types="fl"
declare -A file_types
file_types["f"]="file"
file_types["l"]="symbolic link"
file_types["d"]="directory"
declare -a search_targets
declare -a search_targets_default
search_targets_default=('~/documents')
search_targets=(${search_targets_default[@]})

custom_targets=0
interactive=-1
verbose=0

file_results=""
search=""

help() {
  echo -e "SYNTAX '$SCRIPTNAME [OPTIONS] SEARCH
\nwhere 'OPTIONS' can be\n
  -h, --help  : this help information
  -i [COUNT], --interactive [COUNT]  : enable verification prompt for
                                       each match when more than COUNT
                                       (default: 0) unique match(es)
                                       are found
  -t [TARGETS], --targets [TARGETS]  : override* search target path(s).
                                       TARGETS can either be a path, or
                                       a file containing paths, one
                                       path per line
                                       (default: $rc)
  -ft TYPES, --file-types TYPES  : override the default search file
                                   types (default: fl)
\n    TYPES  : non-delimited list of characters representing a file
             type, supporting:
      f  : file
      l  : symbolic link
      d  : directory
\n  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line
  -v, --verbose                : output additional info
\nand 'SEARCH' is  : a (partial) file name to search for in the list of
                   search target paths*
\n*default: ${search_targets_default[*]}
\n# state
rc: $rc [$([ ! -e "$rc" ] && echo "not ")found]
search target(s):
$(for p in "${search_targets[@]}"; do echo -e "  $p"; done)
" 1>&2
}

option=search

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" 1>&2 && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/^[ ]*-*//g')"
  case "$arg" in
    "h"|"help") option=help ;;
    "i"|"interactive")
      interactive=0
      [[ $# -gt 2 && -z "$(echo "$2" | sed -n '/^[ ]*-\+/p')" ]] && \
        { shift && interactive=$1; } ;;
    "t"|"targets")
      custom_targets=1
      [[ $# -gt 2 && -z "$(echo "$2" | sed -n '/^[ ]*-\+/p')" ]] && \
        { shift && search_targets=("$1"); } || search_targets=("$rc") ;;
    "ft"|"file-types") shift && search_types="$1" ;;
    "r"|"results") shift && file_results="$1" ;;
    "v"|"verbose") verbose=1 ;;
    *) [ -n "$search" ] && help && echo "[error] unknown arg '$arg'" 1>&2; search="$1" ;;
  esac
  shift
done

# option verification
if [ -n "$file_results" ]; then
  [ -d "$(dirname "$file_results")" ] || mkdir -p "$(dirname "$file_results")"
fi
if [ $custom_targets -eq 1 ]; then
  [ ! -e "${search_targets[0]}" ] && echo "[error] invalid custom search targets set '${search_targets[@]}'" 1>&2 && exit 1
  # expand file
  [ -f "${search_targets[0]}" ] && \
    { IFS=$'\n'; search_targets=($(cat "${search_targets[0]}")); IFS="$IFSORG"; }
fi

# run help after option parsing / verification
[ "x$option" = "xhelp" ] && help && exit

declare -a files
declare -a results

[ -z "$search" ] && \
  echo "[error] missing search criteria" 1>&2 && exit 1

if [[ -f "$search" && ("x$(dirname "$search")" != "x." ||
                       "x${search:0:1}" == "x." ||
                       $custom_targets -eq 0) ]]; then
  # differentiate 'search' strings from paths (absolute or relative)
  # assume local file if no custom targets are specified
  [ -n "$(echo "$search_types" | sed -n '/'"$(fn_file_type "--short" "$search")"'/p')" ] && \
    results[${#results[@]}]="$search"
elif [[ "x$(dirname "$search")" != "x." || "x${search:0:1}" == "x." ]]; then
  # create explicit relative files
  if [ $interactive -ge 0 ]; then
    # new file. offer creation
    fn_decision "[user] file '$search' does not exist, create it?" >/dev/null || exit
    # ensure path
    [ -d "$(dirname "$search")" ] || mkdir -p "$(dirname "$search")"
    touch "$search"
    results[${#results[@]}]="$search"
  fi
else
  # use search targets
  IFS=$'\n'; files=($(fn_search_set "$search" 0 "$search_types" "${search_targets[@]}")); IFS="$IFSORG"
  if [ ${#files[@]} -eq 0 ]; then
    IFS=$'\n'; files=($(fn_search_set "$search" 0 "$search_types" "./")); IFS="$IFSORG"
  fi

  for f in "${files[@]}"; do
    if [[ $interactive -eq -1 || ${#files[@]} -le $interactive ]]; then
      results[${#results[@]}]="$f"
    else
      result=""
      res="$(fn_decision "[user] search match, use $(fn_file_type "--long" "$f") '$f'?" "ync")"
      [ "x$res" = "xc" ] && exit  # !break, no partial results
      [ "x$res" = "xn" ] && continue
      results[${#results[@]}]="$f"
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
