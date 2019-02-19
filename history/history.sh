#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

help() {
  echo -e "usage '$SCRIPTNAME target COMMAND1 [COMMAND2] [COMMAND3..]'
\nwhere 'target':\tfile to append command history to
        '[COMMANDx]':\ta command for append approval
"
}

[ $# -lt 1 ] && help && exit 1

target="$1" && shift
if [ ! -f "$target" ]; then
  search="$target"
  target="$(search_ -i "$search")"
  [ ! -f "$target" ] &&\
    echo "[error] searching for target '$search' failed" && exit 1
fi
echo "[info] target file '$target' set"

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
    "a") for l2 in $(seq $l 1 $((${#cmds[@]}-1))); do echo "${cmds[$l2]}" >> "$target"; done; exit 0 ;;
    "e") cmds[$l]="$(fnEditLine "${cmds[$l]}")" ;;
    "n") l=$(($l+1)) && continue ;;
    "x") exit 0 ;;
  esac
done
