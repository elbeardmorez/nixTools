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
commands=("$@")
if [ ${#commands[@]} -eq 0 ]; then
  IFS=$'\n'; commands=($(tail -n10 "$(sh -i -c 'echo $HISTFILE')")); IFS="$IFSORG"
fi
l=0
while [ $l -lt ${#commands[@]} ]; do
  command="$(echo "${commands[$l]}" | sed 's|^\s*[0-9]*\s*\(.*\)$|\1|g')"
  [ -z "$command" ] && l=$(($l+1)) && continue
  echo -n "[user] append command '$command?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: "
  res="$(fnDecision "y|n|e|a|x")"
  case "$res" in
    "y") l=$(($l+1)) && echo "$command" >> "$target" && continue ;;
    "a") for l2 in $(seq $l 1 $((${#commands[@]}-1))); do echo "${commands[$l2]}" >> "$target"; done; exit ;;
    "e") read -e -i "$command" commands[$l] ;;
    "n") l=$(($l+1)) && continue ;;
    "x") exit ;;
  esac
done
