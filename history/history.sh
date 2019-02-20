#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

count=10
declare target
declare -a cmds

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'
\nwhere:\n
  OPTIONS can be:
    -h, --help  : this help information
    -c COUNT, --count COUNT  : read last COUNT history entries
                               (default: 10)
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
    "c"|"count") shift && count=$1 ;;
    *) [ -z "$target" ] && target="$1" || cmds[${#cmds[@]}]="$1" ;;
  esac
  shift
done

# arg validation
## ensure target
if [ ! -f "$target" ]; then
  search="$target"
  target="$(search_ -i "$search")"
  [ ! -f "$target" ] && exit 1
fi
[ $DEBUG -gt 0 ] && echo "[debug] target file '$target' set"
# ensure commands
if [ ${#cmds[@]} -eq 0 ]; then
  # read from stdin
  if [ ! -t 0 ]; then
    # read piped commands
    IFS=$'\n'; cmds=($(cat)); IFS="$IFSORG"
    # ensure a usable pipe for user input
    exec < /dev/tty || (echo "[error] cannot set usable stdin!" && exit 1)
  fi
fi
if [ ${#cmds[@]} -eq 0 ]; then
  # read from history file
  IFS=$'\n'; cmds=($(tail -n$count "$($(fnShell) -i -c 'echo $HISTFILE')" | sed 's/^\s*:\s*[0-9]\{10\}:[0-9]\+;//')); IFS="$IFSORG"
fi

l=0
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
