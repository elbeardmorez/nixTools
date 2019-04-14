#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

rc="$HOME/.nixTools/$SCRIPTNAME"

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
  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line
  -v, --verbose                : output additional info
\nand 'SEARCH' is  : a (partial) file name to search for in the list of
                   search target paths*
\n*default: ${search_targets_default[*]}
\n# state
rc: $rc [$([ ! -e "$rc" ] && echo "not ")found]
search target(s):
$(for p in "${search_targets[@]}"; do echo -e "  $p"; done)
"
}

option=search

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/[ ]*-*//g')"
  case "$arg" in
    "h"|"help") option=help ;;
    "i"|"interactive")
      interactive=0
      [[ $# -gt 2 && -z "$(echo "$2" | sed -n '/[ ]*-\+/p')" ]] && \
        { shift && interactive=$1; } ;;
    "t"|"targets")
      custom_targets=1
      [[ $# -gt 2 && -z "$(echo "$2" | sed -n '/[ ]*-\+/p')" ]] && \
        { shift && search_targets=("$1"); } || search_targets=("$rc") ;;
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
if [ $custom_targets -eq 1 ]; then
  [ ! -e "${search_targets[0]}" ] && echo "[error] invalid custom search targets set '${search_targets[@]}'" && exit 1
  # expand file
  [ -f "${search_targets[0]}" ] && { IFS=$'\n'; search_targets=($(cat "${search_targets[0]}")); IFS="$IFSORG"; }
fi

# run help after option parsing / verification
[ "x$option" == "xhelp" ] && help && exit

declare -a files
declare -a files2
declare -a results
declare -A map

if [[ -f "$search" && $custom_targets -eq 0 ]]; then
  # prioritise local files
  results[${#results[@]}]="$search"
elif [[ ! "x$(dirname "$search")" == "x." || "x${search:0:1}" == "x." ]]; then
  # create file
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
  for p in "${search_targets[@]}"; do
    p="$(eval "echo $p")"  # resolve target
    if [ -e "$p" ]; then
      IFS=$'\n'; files2=($(find $p -name "$search" \( -type f -o -type l \))); IFS="$IFSORG"
      for file in "${files2[@]}"; do
        [ -n "${map["$file"]}" ] && continue  # no dupes
        map["$file"]=1
        files[${#files[@]}]="$file";
      done
    elif [ $verbose -eq 1 ]; then
      echo "[info] path '$p' invalid or it no longer exists, ignoring" 1>&2
    fi
  done

  for file in "${files[@]}"; do
    if [[ $interactive -eq -1 || ${#files[@]} -le $interactive ]]; then
      results[${#results[@]}]="$file"
    else
      result=""
      res="$(fn_decision "[user] search match, use file '$file'?" "ync")"
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
  [ -n "$file_results" ] && echo -e "$results" >> "$file_results"
  echo -e "$results"
else
  [ ${#files[@]} -eq 0 ] &&\
    echo "[info] no matches for search '$search'" 1>&2
fi
