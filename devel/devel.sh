#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG=$IFS
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

#defaults
option='find'

function help() {
  echo -e "
syntax: $SCRIPTNAME [option] [option-arg1 [option-arg2 .. ]]
\noption:
  find  : find extraneous whitespace
    [args]
    target file/dir  : target
    filter  : regexp filter for files to test (default: '.*')
    max-depth  : limit target files to within given hierarchy level
                 (default: 1)
  fix
  fix-c
  debug
  changelog
  commits  : process diffs into fix/mod/hack repo structure
    [args]
    target  : location of repository to extract/use patch set from
              (default: '.')
    prog    : program name (default: target directory name)
    vcs     : version control type, git, svn, bzr, cvs (default: git)
    [count] : number of patches to process (default: 1)
"
}

function fnCommits() {

  target=. && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift 1
  [ $# -lt 1 ] &&  echo "[error] missing 'prog name' argument" && exit 1
  prog="$1" && shift
  vcs=git && [ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(git\|svn\|bzr\)/p')" != "x" ] && vcs="$1" && shift
  count=1 && [ $# -gt 0 ] && count=$1 && shift

  case $vcs in
    "git")
      base="xxx"
      if [ $count -gt 0 ]; then
        cd "$target"
        git format-patch -$count HEAD
        base=`git log --format=oneline | head -n$[$count+1] | tail -n1 | cut -d' ' -f1`
        cd -
      fi
      mkdir -p commits/{fix,mod,hack}
      mv "$target"/00*patch commits/
      # process patches
      cd commits
      for p in 00*patch; do
        # name
        subject=`sed -n 's|Subject: \[PATCH[^]]*\] \(.*\)|\1|p' "$p"`
        name="$subject"
        name=`echo "$name" | sed 's|[ ]|.|g'`
        name=`echo "$name" | sed 's|[\/:]|_|g'`
        p2="`echo "$name" | awk '{print tolower($0)}'`.diff"
        [ $DEBUG -gt 0 ] && echo "moving '$p' -> '$p2'" 1>&2
        mv "$p" "$p2"
        # clean subject
        sed -i 's|^Subject: \[PATCH [^]]*\]|Subject:|' "$p2"
        # get patch type
        type=""
        echo "# prog: $prog | patch: '$p2'"
        echo -ne "set patch type [f]ix/[m]od/[h]ack/e[x]it: " 1>&2
        bRetry=1
        while [ $bRetry -gt 0 ]; do
          result=
          read -s -n 1 result
          case "$result" in
            "f"|"F") echo "$result" 1>&2; bRetry=0; type="fix" ;;
            "m"|"M") echo "$result" 1>&2; bRetry=0; type="mod" ;;
            "h"|"H") echo "$result" 1>&2; bRetry=0; type="hack" ;;
            "x"|"X") echo "$result" 1>&2; return 1 ;;
          esac
        done
        mkdir -p "$type/$prog"
        mv "$p2" "$type/$prog/"
        # append patch to repo readme
        entry="$p2 [git sha:$base | pending]"
        if [ -e $type/README ]; then
          # search for existing program entry
          if [ "x`sed -n '/^### '$prog'$/p' "$type/README"`" == "x" ]; then
            echo -e "### '$prog\n-$entry\n" >> $type/README
          else
            # insert entry
            sed -n -i '/^### '$prog'$/,/^$/{/^$/{x;s/\n\(.*\)/\1\n'-"$entry"'\n/p;b;};H;b;};p;' "$type/README"
          fi
        else
          echo -e "\n### $prog\n-$entry\n" >> "$type/README"
        fi
        # append patch details to program specific readme
        comments=`sed -n '/^Subject/,/^\-\-\-/{/^\-\-\-/{x;s/Subject[^\n]*//;s/^\n*//;p;b;};H;b;}' "$type/$prog/$p2"`
        echo -e "\n# $entry" >> "$type/$prog/README"
        [ "x$comments" != "x" ] && echo "$comments" >> "$type/$prog/README"
      done
      cd -
      ;;
    *)
      echo "[user] vcs type: '$vcs' not implemented" && exit 1
      ;;
  esac
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
[ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(help\|--help\|-h\|find\|fix\|fix-c\|debug\|changelog\|commits\)/p')" != "x" ] && option="$1" && shift

case "$option" in
  "help"|"--help"|"-h")
    help
    ;;
  "commits")
    fnCommits "$@"
    ;;
  "changelog")
    fnChangelog "$@"
    ;;
  "debug")
    fnDebug "$@"
    ;;
  "find"|"fix"|"fix-c")
    fnProcess "$@"
    ;;
  *)
    help
    ;;
esac
