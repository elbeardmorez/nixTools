#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

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
  supported_languages="c c++ javascript"

  declare language_default
  declare language
  declare -A debuggers
  declare -A debugger_args
  declare -A debugger_args_template
  declare args_pt

  # c
  debuggers["c"]="gdb"
  debugger_args["c"]="NAME PID _ARGS_"
  debugger_args_template["c"]="NAME PID|--pid=PID _ARGS_"
  # c++
  debuggers["c++"]="gdb"
  debugger_args["c++"]="NAME PID _ARGS_"
  debugger_args_template["c++"]="NAME PID|--pid=PID _ARGS_"
  # javascript
  debuggers["javascript"]="node"
  debugger_args["javascript"]="SRC PORT _ARGS_"
  debugger_args_template["javascript"]="PORT|--inspect-brk=PORT SRC _ARGS_"

  language_default=c
  args_pt=""
  declare -a args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-+/,"",$0); print(tolower($0))}')"
    if [ ${#arg} -lt ${#1} ]; then
      # process named options
      case "$arg" in
        "l"|"language") shift && language="$1" ;;
        "")
          # pass-through remaining args
          shift
          s="";
          while [ -n "$1" ]; do s="$s $(fn_escape "space" "$1")"; shift; done
          args_pt="${s:1}"
          continue;
          ;;
        *) help && echo "[error] unrecognised arg '$1'" && return 1
      esac
    else
      args[${#args[@]}]="$1"
    fi
    shift
  done

  # validate args
  [[ -n "$language" && \
     -z "$(echo "$language" | \
       sed -n '/^\('"$(echo "$supported_languages" | \
         sed 's/ /\\|/g')"'\)$/p')" ]] && \
    help && echo "[error] unsupported language '$language'" && return 1

  language=${language:-$language_default}

  declare bin
  declare -a bin_args

  bin="${debuggers["$language"]}"

  _ARGS_="-- _ARGS_"
  case "$bin" in
    "gdb") _ARGS_="-ex 'set args _ARGS_'" ;;
  esac

  # deduce, consume, or calculate arg values
  args_ns=(${debugger_args["$language"]})
  declare -A arg_vs
  declare args_idx
  args_idx=0
  for arg_n in "${args_ns[@]}"; do
    n="$arg_n"
    v="$(eval 'echo "$'$n'"')"
    [[ -z "$v" && -n "${args[$args_idx]}" ]] && \
      v="${args[$args_idx]}" && args_idx=$((args_idx + 1))
    # special handling
    case "$n" in
      "_ARGS_")
        [ -z "$args_pt" ] && \
          v="" || \
          v="$(echo "$v" | sed 's/'"$n"'/'"$(fn_escape "path" "$args_pt")"'/')"
        ;;
      "PID")
        [ -n "$v" ] && continue
        name="${arg_vs["NAME"]}"
        [ -z "$name" ] && continue
        declare proc
        declare select
        select=0
        pgrep="$(which pgrep)"
        if [ -n "$pgrep" ]; then
          IFS=$'\n'; proc=($(pgrep -x -a "$name")); IFS="$IFSORG"
          if [ ${#proc[@]} -eq 0 ]; then
            IFS=$'\n'; proc=($(pgrep -f -a "$name")); IFS="$IFSORG"
            if [ ${#proc[@]} -gt 0 ]; then
              echo "[info] no exact process matched '$name'. " \
                   "full command line search found ${#proc[@]} " \
                   "possibilit$([ ${#proc[@]} -eq 1 ] && echo "y" \
                                                      || echo "ies")"
              select=1  # force
            fi
          fi
        else
          pidof="$(which pidof)"
          if [ -z "$pidof" ]; then
            echo "[info] missing pgrep / pidof binaries, cannot " \
                 "identify target process for debugging"
          else
            IFS=$'\n'; proc=($(pidof "$name")); IFS="$IFSORG"
          fi
        fi
        if [[ ${#proc[@]} -gt 1 || $select -eq 1 ]]; then
          opts=""
          lmax="${#proc[@]}"
          llmax=${#lmax}
          pmax="${proc[$((${#proc[@]} - 1))]}"
          p_max="${pmax%% *}"
          lp_max="${#p_max}"
          l=0
          for ps in "${proc[@]}"; do
            l=$((l + 1))
            opts+="|$l"
            ps_="${ps%% *}"
            printf "%$((llmax - ${#l}))s[%d] %$((lp_max - ${#ps_}))s%s\n" "" $l "" "$ps_ | ${ps#* }"
          done
          opts="${opts:1}|x"
          prompt="select item # or e(${CLR_HL}x${CLR_OFF})it "
          prompt+="[${CLR_HL}1${CLR_OFF}-${CLR_HL}$l${CLR_OFF}"
          prompt+="|${CLR_HL}x${CLR_OFF}]"
          res="$(fn_decision "$(echo -e "$prompt")" "$opts" 0 0 1)"
          if [ "x$res" != "xx" ]; then
            ps="${proc[$((res - 1))]}"
            v="${ps%% *}"
          fi
        fi
        ;;
    esac
    [ -n "$v" ] && arg_vs["$n"]="$v"
  done
  # replace template placeholders with any available values
  args_ts=(${debugger_args_template["$language"]})
  for arg_t in "${args_ts[@]}"; do
    n="${arg_t%%|*}"
    t="${arg_t#*|}"
    v="${arg_vs["$n"]}"
    [ -n "$v" ] && bin_args[${#bin_args[@]}]="$(echo "$t" | sed 's/'"$n"'/'"$(fn_escape "path" "$v")"'/')"
  done

  # execute
  fn_decision "[user] debug: $bin ${bin_args[*]} ?" >/dev/null || return 0
  eval "$bin ${bin_args[*]}"
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
