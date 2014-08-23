#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG=$IFS
TEST=${TEST:-0}

#defaults
option='find'

function help() {
  echo -e "
syntax: $SCRIPTNAME [option] [option-arg1 [option-arg2 .. ]]
\noption:
  find\t\t: find extraneous whitespace
  \t\t  args:
  \t\t    target file/dir: target
  \t\t    filter\t: regexp filter for files to test, defaulting to '.*'
  \t\t    max-depth\t: limit target files to within given hierarchy level. defaulting to '1'
  fix
  fix-c
  debug
  changelog
"
}

function fnChangelog() {

  target=. && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift 1
  vcs=git && [ $# -gt 0 ] && [ "x`echo "$1" | sed -n '/\(git\|svn\|bzr\)/p'`" != "x" ] && vcs="$1" && shift

  cd "$target"
  #*IMPLEMENT repo test or die
  fTmp=`tempfile`
  case $vcs in
    "git")
      if [ -f ./ChangeLog ]; then
        merge=0
        # valid last logged commit?
        commit=`head -n1 ChangeLog | sed -n 's/.*version \(\S*\).*/\1/p'`
        if [ "x$commit" != "x" ]; then
          echo "+current ChangeLog head commit: '$commit'"
          if [ "x`git log --format=oneline | grep "$commit"`" != "x" ]; then
            echo "-commit is valid, using it!"
            merge=1
          else
            echo "-commit is invalid!"
            commit=""
          fi
        fi
        # valid first commit?
        if [ "x$commit" == "x" ]; then
          commit=`git log --format=oneline | tail -n 1 | cut -d' ' -f1`
          echo "+first project commit: '$commit'"
          if [ "x`grep "$commit" ChangeLog`" != "x" ]; then
            echo "-found in ChangeLog"
            merge=1
          else
            echo "-not found in ChangeLog"
          fi
        fi
        git log -n 1 $commit 2>/dev/null 1>&2
        [ $? -eq 0 ] && commits=`git log --pretty=oneline $commit.. | wc -l`

        if [ $merge -eq 1 ]; then
          echo "+clearing messages"
          sed -i -n '0,/.*'$commit'\s*/{/.*'$commit'\s*/p;b;};p' ChangeLog
          echo "+merging"
        fi
      else
        echo "+new ChangeLog"
        touch ./ChangeLog
        commits=`git log --pretty=oneline | wc -l`
      fi

      echo "+$commits commit`[ $commits -gt 1 ] && echo "s"` to add to ChangeLog"
      [ $commits -eq 0 ] && exit 0

      git log -n $commits --pretty=format:"%at version %H%n - %s (%an)" | awk '{if ($1 ~ /[0-9]+/) {printf strftime("%Y%b%d",$1); $1=""}; print $0}' | cat - ChangeLog > $fTmp && mv $fTmp ChangeLog
      cd ->/dev/null

      ;;
    *)
     echo "[user] vcs type: '$vcs' not implemented" && exit 1
     ;;
  esac
}

function fnDebug() {
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
}

function fnProcess() {

  case "$option" in
    "find")
      target="." && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift
      filter=".*" && [ $# -gt 0 ] && filter="$1" && shift
      maxdepth=1 && [ $# -gt 0 ] && maxdepth="$1" && shift
      sFiles=()
      IFS=$'\n'
      if [ -f "$target" ]; then
        sFiles=("$target")
      elif [ -d "$target" ]; then
        sFiles=($(find "$target" -iregex "$filter" -maxdepth $maxdepth))
      fi
      IFS="$IFSORG"

      SEDCMD="$([ $TEST -gt 0 ] && echo "echo ")sed"
      for f in "${sFiles[@]}"; do
        echo -e "\n##########"
        echo -e "#searching for 'braces after new line' in file '$f'\n"
        sed -n 'H;x;/.*)\s*\n\+\s*{.*/p' "$f"
        echo -e "\n##########"
        echo -e "#searching for 'tab' character' in file '$f'\n"
        sed -n 's/\t/<TAB>/gp' "$f"
        echo -e "\n##########"
        echo -e "#searching for 'trailing white-space' in file '$f'\n"
        IFS=$'\n'; lines=$(sed -n '/\s$/p' "$f"); IFS=$IFSORG
        for line in "${lines[@]}"; do
          echo "$line" | sed -n ':1;s/^\(.*\S\)\s\(\s*$\)/\1·\2/;t1;p'
        done
      done
      ;;

    "fix")
      target="." && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift
      filter=".*" && [ $# -gt 0 ] && filter="$1" && shift
      maxdepth=1 && [ $# -gt 0 ] && maxdepth="$1" && shift
      sFiles=()
      IFS=$'\n'
      if [ -f "$target" ]; then
        sFiles=("$target")
      elif [ -d "$target" ]; then
        sFiles=($(find "$target" -iregex "$filter" -maxdepth $maxdepth))
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
  esac
}

# args
[ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(help\|--help\|-h\|find\|fix\|fix-c\|debug\|changelog\)/p')" != "x" ] && option="$1" && shift

case "$option" in
  "help"|"--help"|"-h")
    help
    ;;
  "changelog")
    fnChangelog "$@"
    ;;
  "debug")
    fnDebug "$@"
    ;;
  *)
    fnProcess "$@"
    ;;
esac
