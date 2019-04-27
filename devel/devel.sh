#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG=$IFS
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

#defaults
option='find'

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]
\nwith OPTION:
  find  : find extraneous whitespace
    ARGS:
    target file/dir  : target
    filter  : regexp filter for files to test (default: '.*')
    [max-depth]  : limit target files to within given hierarchy level
                   (default: 1)
  fix
  fix-c
  debug
  changelog
  commits  : process diffs into fix/mod/hack repo structure
    ARGS:
    target  : location of repository to extract/use patch set from
              (default: '.')
    prog    : program name (default: target directory name)
    vcs     : version control type, git, svn, bzr, cvs (default: git)
    [count] : number of patches to process (default: 1)
"
}

fn_commits() {

  target="$PWD" && [ $# -gt 0 ] && [ -e "$1" ] && target="`cd "$1"; pwd`" && shift
  source="$target" && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift
  prog=`cd "$source"; pwd` && prog="${prog##*/}" && [ $# -gt 0 ] && prog="$1" && shift
  vcs=git && [ $# -gt 0 ] && [ "x`echo "$(cd "$source"; pwd)" | sed -n '/\(git\|svn\|bzr\)/p'`" != "x" ] && vcs="$1" && shift
  count=1 && [ $# -gt 0 ] && count=$1 && shift

  case $vcs in
    "git")
      commithash="xxx"
      if [ $count -gt 0 ]; then
        cd "$source"
        git format-patch -$count HEAD
        cd - >/dev/null
      fi
      if [[ ! -e "$target"/fix ||
           ! -e "$target"/mod ||
           ! -e "$target"/hack ]]; then
        mkdir -p commits/{fix,mod,hack}
        cd commits
      else
        cd "$target"
      fi

      mv "$source"/00*patch ./
      # process patches
      for p in 00*patch; do
        #commithash=`cd $source; git log --format=oneline | head -n$[$count] | tail -n1 | cut -d' ' -f1; cd - 1>/dev/null`
        commithash=`head -n1 "$p" | cut -d' ' -f2`
        date=`head -n3 "$p" | sed '$!d;s/Date: //'`
        # name
        subject=`sed -n '/^Subject/{N;s/\n//;s|^Subject: \[PATCH[^]]*\] \(.*\)|\1|p}' "$p"`
        name="$subject"
        name=`echo "$name" | sed 's|[ ]|.|g'`
        name=`echo "$name" | sed 's|[\/:]|_|g'`
        p2="`echo "$name" | awk '{print tolower($0)}'`.diff"
        [ $DEBUG -gt 0 ] && echo "moving '$p' -> '$p2'" 1>&2
        mv "$p" "$p2"
        # clean subject
        sed -i 's|^Subject: \[PATCH[^]]*\]|Subject:|' "$p2"
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
        entry="$p2 [git sha:$commithash | `[ "x$type" == "xhack" ] && echo "unsubmitted" || echo "pending"`]"
        if [ -e $type/README ]; then
          # search for existing program entry
          if [ "x`sed -n '/^### '$prog'$/p' "$type/README"`" == "x" ]; then
            echo -e "### $prog\n-$entry\n" >> $type/README
          else
            # insert entry
            sed -n -i '/^### '$prog'$/,/^$/{/^### '$prog'$/{h;b};/^$/{x;s/\(.*\)/\1\n-'"$entry"'\n/p;b;}; H;$!b};${x;/^### '$prog'/{s/\(.*\)/\1\n-'"$entry"'/p;b;};x;p;b;};p' "$type/README"
          fi
        else
          echo -e "\n### $prog\n-$entry\n" >> "$type/README"
        fi
        # append patch details to program specific readme
        comments=`sed -n '/^Subject/,/^\-\-\-/{/^\-\-\-/{x;s/Subject[^\n]*//;s/^\n*//;p;b;};H;b;}' "$type/$prog/$p2"`
        echo -e "\n# $entry" >> "$type/$prog/README"
        [ "x$comments" != "x" ] && echo "$comments" >> "$type/$prog/README"

        # commit commands
        echo "commit: git add .; GIT_AUTHOR_DATE='$date' GIT_COMMITTER_DATE='$date' git commit"
      done

      echo "# patches added to fix/mod/hack hierarchy at '$target'"

      cd - >/dev/null
      ;;
    *)
      echo "[user] vcs type: '$vcs' not implemented" && exit 1
      ;;
  esac
}

fn_changelog() {

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

fn_debug() {

  declare supported_languages
  supported_languages="c c++"

  declare language_default
  declare language
  declare -A debuggers
  declare -A debugger_args

  # c
  debuggers["c"]="gdb"
  debugger_args["c"]="NAME|NAME PID|--pid=PID"
  # c++
  debuggers["c++"]="gdb"
  debugger_args["c++"]="NAME|NAME PID|--pid=PID"

  language_default=c
  arg=$1
  [ -n "$(echo "$arg" | sed -n '/^\('"$(echo "$supported_languages" | sed 's/ /\|/g')"'\)$/p')" ] && language="$arg" && shift
  language=${language:-$language_default}

  declare bin
  declare -a bin_args

  bin="${debuggers["$language"]}"

  args=(${debugger_args["$language"]})
  declare -A arg_vs
  for arg in "${args[@]}"; do
    n="${arg%%|*}"
    t="${arg#*|}"
    v="$(eval 'echo "$'$n'"')"
    [[ -z "$v" && -n "$1" ]] && v="$1" && shift
    if [ -z "$v" ]; then
      # special handling
      case "$n" in
        "PID")
          name="${arg_vs["NAME"]}"
          [ -z "$name" ] && continue
          v=$(pgrep -x "$name")
          [ -z "$v" ] && v="$(pidof $name)"
          ;;
      esac
    fi
    if [ -n "$v" ]; then
      arg_vs["$n"]="$v"
      bin_args[${#bin_args[@]}]="$(echo "$t" | sed 's/'"$n"'/'"$v"'/')"
    fi
  done

  # execute
  echo -n "[user] debug: $debugger $debugger_args ? [(y)es/(n)o]:  "
  retry=1
  while [ $retry -eq 1 ]; do
    echo -en '\033[1D\033[K'
    read -n 1 -s result
    case "$result" in
      "n" | "N") echo -n $result; retry=0; echo ""; exit ;;
      "y" | "Y") echo -n $result; retry=0 ;;
      *) echo -n " " 1>&2
    esac
  done
  echo ""

  $bin ${bin_args[*]}
}

fn_process() {

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
    fn_commits "$@"
    ;;
  "changelog")
    fn_changelog "$@"
    ;;
  "debug")
    fn_debug "$@"
    ;;
  "find"|"fix"|"fix-c")
    fn_process "$@"
    ;;
  *)
    help
    ;;
esac
