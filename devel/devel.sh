#!/bin/sh
SCRIPTNAME="${0##*/}"

LANGUAGEDEFAULT=c
declare -A type
declare -A typeargs

type["c"]="gdb"
typeargs["c"]="\$NAME --pid=\$PID"

NAME="$1"
PID="${PID:-$2}"

LANGUAGE=${LANGUAGE:-$LANGUAGEDEFAULT}

DEBUGGER="${type["$LANGUAGE"]}"
DEBUGGERARGS="${typeargs["$LANGUAGE"]}"

arrDynamic=("NAME" "PID")
for arg in "${arrDynamic[@]}"; do
  case "$arg" in
    "PID")
      PID=${PID:-$(pgrep -x "$NAME")}
      if [ "x$PID" != "x" ]; then
        DEBUGGERARGS=$(echo "$DEBUGGERARGS" | sed 's|\$'$arg'|'$PID'|')
      else
        DEBUGGERARGS=$(echo "$DEBUGGERARGS" | sed 's|--pid=\$PID||')
      fi
      ;;
    *) DEBUGGERARGS=$(echo "$DEBUGGERARGS" | sed 's|\$'$arg'|'${!arg}'|') ;;
  esac
done

#execute
echo -n "[user] debug: $DEBUGGER $DEBUGGERARGS ? [(y)es/(n)o]:  "
bRetry=1
while [ $bRetry -eq 1 ]; do
  echo -en '\033[1D\033[K'
  read -n 1 -s result
  case "$result" in
    "n" | "N") echo -n $result; bRetry=0; echo ""; exit ;;
    "y" | "Y") echo -n $result; bRetry=0 ;;
    *) echo -n " " 1>&2
  esac
done
echo ""

$DEBUGGER $DEBUGGERARGS
