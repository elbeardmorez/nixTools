#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG=$IFS
TEST=${TEST:-0}

function process()
{
  option="$1" && shift
  case "$option" in
    "find")
      target="$1" && shift
      [ ! -e "$target" ] &&  echo "[error] invalid target file/dir: '$target'" && exit 1
      file="$1"
      echo -e "\n##########"
      echo -e "#searching for 'braces after new line' in file '$file'\n"
      sed -n 'H;x;/.*)\s*\n\+\s*{.*/p' "$file"
      echo -e "\n##########"
      echo -e "#searching for 'tab' character' in file '$file'\n"
      sed -n 's/\t/<TAB>/gp' "$file"
      echo -e "\n##########"
      echo -e "#searching for 'trailing white-space' in file '$file'\n"
      IFS=$'\n'; lines=$(sed -n '/\s$/p' "$file"); IFS=$IFSORG
      for line in "${lines[@]}"; do
        echo "$line" | sed -n ':1;s/^\(.*\S\)\s\(\s*$\)/\1·\2/;t1;p'
      done
      ;;

    "fix")
      target="$1" && shift
      [ ! -e "$target" ] &&  echo "[error] invalid target file/dir: '$target'" && exit 1
      filter=".*" && [ $# -gt 0 ] && filter="$1" && shift
      sFiles=()
      IFS=$'\n'
      if [ -f "$target" ]; then
        sFiles=("$target")
      elif [ -d "$target" ]; then
        sFiles=($(find "$target" -iregex "$filter"))
      fi
      IFS="$IFSORG"

      SEDCMD="$([ $TEST -gt 0 ] && echo "echo ")sed"
      for f in "${sFiles[@]}"; do
        # replace tabs with double spaces
        $SEDCMD -i 's/\t/  /g' "$f"
        # remove trailing whitespace
        $SEDCMD -i 's/\s*$//g' "$f"
      done
      ;;

    "fix-c")
      file="$1"
      indent -bap -bbb -br -brs -cli2 -i2 -sc -sob -nut -ce -cdw -saf -sai -saw -ss -nprs -npcs -l120 "$file"
      ;;

    "debug")
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
      ;;
  esac
}

[ $# -lt 2 ] && echo "[error] arguments 'option' 'option-arg1 ['option-arg2 .. ]" && exit 1
option="$1" && shift
process "$option" "$@"
