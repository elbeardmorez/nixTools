#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

DEFAULT_COUNT=10
declare count
declare target
silent=0
declare -a cmds
filter='s/\s*\(:\s*[0-9]\{10\}:[0-9]\+;\|[0-9]\+\)\s*//'
declare -a blacklist
filter_last=1
blacklist[${#blacklist[@]}]="$SCRIPTNAME"

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'
\nwhere:\n
  OPTIONS can be:
    -h, --help  : this help information
    -c [COUNT], --count [COUNT]  : read last COUNT history entries
                                   (default: 10)
    -s. --silent  : disable info messages
    -nfl. --no-filter-last  : don't attempl to filter lsst commands
                              (e.g. the call to this script)
\n  TARGET  : is a file to append commands to
\n  COMMANDs  : are a set of commands to verify
\nnote: where no COMMAND args are passed, the file specified by
      HISTFILE will be used as a source
"
}

# process args
[ $# -lt 1 ] && help && echo "[error] not enough args!" && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk '{gsub(/^ *-*/,"",$0); print(tolower($0))}')"
  case "$arg" in
    "h"|"help") help && exit 0 ;;
    "c"|"count") count=$DEFAULT_COUNT && shift && [[ $# -gt 1 && -n "$(echo "$1" | sed -n '/^[0-9]\+$/p')" ]] && count=$1 ;;
    "s"|"silent") silent=1 ;;
    "nfl"|"no-filter-last") filter_last=0 ;;
    *) [ -z "$target" ] && target="$1" || cmds[${#cmds[@]}]="$1" ;;
  esac
  shift
done
[ $silent -ne 1 ] && echo "[info] added ${#cmds[@]} command$([ ${#cmds[@]} -ne 1 ] && echo "s") from args"

# arg validation
filter_blacklist=""
[ $filter_last -eq 1 ] &&\
  for s in "${blacklist[@]}"; do filter_blacklist+="\|$s"; done &&\
  filter_blacklist=${filter_blacklist:2}
## ensure commands
if [ ! -t 0 ]; then
  x=${#cmds[@]}
  # read piped from stdin
  IFS=$'\n'; cmds_next=($(sed "$filter"$([ $filter_last -eq 1 ] && echo ';${/\('"$filter_blacklist"'\)/d;}'))); IFS="$IFSORG"
  cmds=("${cmds[@]}" "${cmds_next[@]}")
  [ $silent -ne 1 ] && echo "[info] added $((${#cmds[@]}-x)) command$([ $((${#cmds[@]}-x)) -ne 1 ] && echo "s") from stdin"
fi
if [[ -n "$count" || ${#cmds[@]} -eq 0 ]]; then
  x=${#cmds[@]}
  # read from history file
  histfile="$($(fnShell) -i -c 'echo $HISTFILE' 2>/dev/null)"
  IFS=$'\n'; cmds_next=($(tail -n$([ $filter_last -eq 1 ] && echo $(($count+1)) || echo $count) "$histfile" | sed "$filter"$([ $filter_last -eq 1 ] && echo ';${/\('"$filter_blacklist"'\)/d;}'))); IFS="$IFSORG"
  [ ${#cmds_next[@]} -gt $count ] &&\
    cmds_next=("${cmds_next:1}")  # filter wasn't hit
  cmds=("${cmds[@]}" "${cmds_next[@]}")
  [ $silent -ne 1 ] && echo "[info] added $((${#cmds[@]}-x)) command$([ $((${#cmds[@]}-x)) -ne 1 ] && echo "s") from history file '$histfile'"
fi
# ensure a usable pipe for user input
if [ ! -t 0 ]; then
  # pipes are inherited so the parent's stdin will be untouched
  exec < /dev/tty || (echo "[error] cannot set usable stdin!" && exit 1)
fi
## ensure target
if [ ! -f "$target" ]; then
  search="$target"
  target="$(search_ -i "$search")"
  [ ! -f "$target" ] && exit 1
fi
[ $silent -ne 1 ] && echo "[info] target file '$target' set"

l=0
[ $silent -ne 1 ] && echo "[info] ${#cmds[@]} command$([ ${#cmds[@]} -ne 1 ] && echo "s") for consideration"
while [ $l -lt ${#cmds[@]} ]; do
  cmd="${cmds[$l]}"
  [ -z "$cmd" ] && l=$(($l+1)) && continue
  echo -n "[user] append command '$cmd?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: "
  res="$(fnDecision "y|n|e|a|x")"
  case "$res" in
    "y") l=$(($l+1)) && echo "$cmd" >> "$target" && continue ;;
    "a") for l2 in $(seq $l 1 $((${#cmds[@]}-1))); do echo "${cmds[$l2]}" >> "$target"; done; exit 0 ;;
    "e") cmds[$l]="$(fnEditLine "${cmds[$l]}")" ;;
    "n") l=$(($l+1)) && continue ;;
    "x") exit 0 ;;
  esac
done
