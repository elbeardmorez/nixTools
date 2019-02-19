#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

declare target
declare -a cmds

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'
\nwhere:\n
  OPTIONS can be:
    -h, --help  : this help information
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
    *) [ -z "$target" ] && target="$1" || cmds[${#cmds[@]}]="$1" ;;
  esac
  shift
done

# arg validation
if [ ! -f "$target" ]; then
  search="$target"
  target="$(search_ -i "$search")"
  [ ! -f "$target" ] && exit 1
fi
echo "[info] target file '$target' set"

if [ ${#cmds[@]} -eq 0 ]; then
  IFS=$'\n'; cmds=($(tail -n10 "$($(fnShell) -i -c 'echo $HISTFILE')" | sed 's/^\s*:\s*[0-9]\{10\}:[0-9]\+;//')); IFS="$IFSORG"
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
