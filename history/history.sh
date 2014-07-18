#!/bin/sh
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
for command in "${commands[@]}"; do
  command=$(echo $command | sed 's|^\s*[0-9]*\s*\(.*\)$|\1|g') 
  if [ ! "x$command" == "x" ]; then
    bRetry=1
    bAdd=0
    while [ "$bRetry" -eq 1 ]; do
      if [[ "x$result" == "xa" || "x$result" == "xA" ]]; then
        bRetry=0; bAdd=1
      else
        echo -n "append command: $command? [(y)es/(n)o/(e)dit/(a)ll/e(x)it] "
        bRetry2=1
        while [ "$bRetry2" -eq 1 ]; do
          read -n 1 -s result
          case "$result" in
            "y"|"Y"|"a"|"A") echo $result; bRetry2=0; bRetry=0; bAdd=1 ;;
            "n"|"N") echo $result; bRetry2=0; bRetry=0 ;;  
            "e"|"E") echo $result; bRetry2=0; read -e -i "$command" command ;;
            "x"|"X") echo $result; exit 0 ;;
          esac
        done
      fi 
      [ $bAdd -eq 1 ] && echo "$command" >> "$target" && bAdd=0
    done
  fi
done
