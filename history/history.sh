#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

function help
{
  echo -e "usage '$SCRIPTNAME target COMMAND1 [COMMAND2] [COMMAND3..]'\n"
  echo -e "where 'target':\tfile to append command history to"
  echo -e "      '[COMMANDx]':\ta command for append approval"
  echo ""
}
if [ $# -lt 1 ]; then
  help
  exit 1
fi

target=$1
if [ ! -f "$target" ]; then
  target=$(search_ "$target")
  if [ ! -f "$target" ]; then
    echo "[error] cannot find existing target file: '$1'"
    exit 1
  fi
fi
shift

echo "[user] target file: '$target'"

declare -a cmds
cmds=("$@")
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
    "a") for l2 in $(seq $l 1 $((${#cmds[@]}-1))); do echo "${cmds[$l2]}" >> "$target"; done; exit ;;
    "e") cmds[$l]="$(fnEditLine "${cmds[$l]}")" ;;
    "n") l=$(($l+1)) && continue ;;
    "x") exit ;;
  esac
done
