#!/bin/sh
SCRIPTNAME=${0##*/}
IFSORG="$IFS"

DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

declare max_message; max_message=150

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION]
\nwith OPTION:
\n  log [r]X [[r]X2]  : output log information for commit(s) X:
\n    with supported X:
      [X : 1 <= X <= 25]  : last x commits (-r-X..)
      [X : X > 25]        : revision X (-rX)
      [+X : 1 <= X <= ..] : revision X (-rX)
      [rX : 1 <= X <= ..] : revision X (-rX)
      [-X : X <= -1]      : last X commits (-r-X..)
      [rX_1 rX_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision X_1 and revision X_2 inclusive
          (-r'min(X_1,X_2)'..'max(X_1,X_2)')
      [-X_1 -X_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision 'HEAD - X_1' and revision
          'HEAD - X_2' inclusive (-r'-min(X_1,X_2)'..-'max(X_1,X_2)')
\n  diff [REVISION]  : show diff of REVISION again previous
                     (default: HEAD)
  patch [REVISION] [TARGET]  : format REVISION (default: HEAD) as a
                               diff patch file with additional
                               context information inserted as a
                               header to TARGET (default: auto-
                               generated from commit message)
  commits [SEARCH] [TYPE]  : search log for commits containing SEARCH
                             in TYPE field
\n    with support TYPE:
      message  : search the message content (default)
      author  : search the author field
      committer  : search the commiter field
\n  commits-dump TARGET [SEARCH] [TYPE]
    : wrapper for 'commits' which also dumps any matched commits
      to TARGET
"
}

fn_log() {
  # validate arg(s)
  rev1=-1 && [ $# -gt 0 ] && rev1="$1" && shift
  [ "x$(echo $rev1 | sed -n '/^[-+r]\?[0-9]\+$/p')" == "x" ] &&
    echo "[error] invalid revision arg '$rev1'" && exit 1
  rev2="" && [ $# -gt 0 ] && rev2="$1" && shift
  [ "x$rev2" != "x" ] && [ "x$(echo $rev2 | sed -n '/^[-+r]\?[0-9]\+$/p')" == "x" ] &&
    echo "[error] invalid revision arg '$rev2'" && exit 1

  # tokenise
  IFS=$'\n' && tokens=($(echo " $rev1 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p')) && IFS="$IFSORG"
  rev1prefix="$(echo ${tokens[0]} | tr -d ' ')"
  rev1="$(echo ${tokens[1]} | tr -d ' ')"
  rev1suffix="$(echo ${tokens[2]} | tr -d ' ')"
  tokens=("" "" "")
  [ "x$rev2" != "x" ] &&
    IFS=$'\n' && tokens=($(echo " $rev2 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p')) && IFS="$IFSORG"
  rev2prefix="$(echo ${tokens[0]} | tr -d ' ')"
  rev2="$(echo ${tokens[1]} | tr -d ' ')"
  rev2suffix="$(echo ${tokens[2]} | tr -d ' ')"
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fn_log] rev1: '$rev1prefix|$rev1|$rev1suffix' $([ "x$rev2" != "x" ] && echo "rev2: '$rev2prefix|$rev2|$rev2suffix'")" 1>&2
  # mod
  [[ "x$rev1prefix" == "x" && $rev -le 25 ]] && rev1prefix="-"
  [ "x$rev1prefix" == "x+" ] && rev1prefix=""
  [ "x$rev1prefix" == "xr" ] && rev1prefix=""
  if [ "x$rev2" != "x" ]; then
    rev1suffix=".."
    [[ "x$rev1prefix" == "x" && $rev1 -gt $rev2 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    [[ "x$rev1prefix" == "x-" && $rev2 -gt $rev1 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    rev2prefix=$rev1prefix
  fi
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fn_log] rev1: '$rev1prefix|$rev1|$rev1suffix'$([ "x$rev2" != "x" ] && echo " rev2: '$rev2prefix|$rev2|$rev2suffix'")" 1>&2

  [ $TEST -eq 0 ] && bzr log -r$rev1prefix$rev1$rev1suffix$rev2prefix$rev2$rev2suffix
}

fn_diff() {
  bzr diff -c${1:-"-1"}
}

fn_patch() {
  revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
  target=""
  if [ $# -gt 0 ]; then
    target="$1" && shift
  else
    target=$(fn_log $revision | sed -n '/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/\1\2/;s/ /./g;s/^\.//g' | sed 's/^[-.*]*\.//g' | sed 's/[/`]/./g' | sed 's/\.\././g' | awk '{print tolower($0)}')
    target="$([ $revision -eq -1 ] && echo "0001" || echo "$revision").${target:0:maxmessagelength}.diff"
  fi
  bzr log -c$revision | sed 's/^/#/' > "$target"
  fn_diff $revision >> "$target"
}

fn_commits() {
  declare search; search="$1" && shift
  declare search_type; search_type="message"
  [ $# -gt 0 ] && search_type="$1"
  bzr log --match-$search_type=".*$search.*" | sed -n '/^revno:.*/,/^-\+$/{/^revno:.*/{s/^revno: \([0-9]\+\)/\1|/;H;b};/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H}};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/r\1\2/;s/ /./g' | awk '{print tolower($0)}'
}

fn_commits_dump() {
  declare target; target="$1" && shift
  declare -a commits
  declare commit
  declare revision
  declare message
  declare file
  [ ! -d "$target" ] && mkdir -p "$target" 2>/dev/null
  echo "target: '$target'"
  commits=($(fn_commits "$@"))
  for commit in "${commits[@]}"; do
    revision="${commit%%|*}"
    message="${commit:$((${#revision} + 1)):max_message}"
    file=${revision}.${message}.diff
    echo "revision: '$revision', file: '$file'"
    fn_patch "${revision#r}" "$target/$file"
  done
}

fn_test() {
  type=${1:-log}
  case "$type" in
    "log")
      TEST=1
      echo ">log r12 r15" && fn_log r12 r15
      echo ">log r15 r12" && fn_log r15 r12
      echo ">log 12 15" && fn_log 12 15
      echo ">log -12 -15" && fn_log -12 -15
      echo ">log -15 -12" && fn_log -15 -12
      echo ">log -10" && fn_log -10
      echo ">log 10" && fn_log 10
      echo ">log +10" && fn_log +10
      echo ">log r10" && fn_log r10
      ;;
  esac
}

command=help && [ $# -gt 0 ] && command="$1" && shift
case "$command" in
  "help") help ;;
  "diff") fn_diff "$@" ;;
  "log") fn_log "$@" ;;
  "patch"|"formatpatch"|"format-patch") fn_patch "$@" ;;
  "commits") fn_commits "$@" ;;
  "commits-dump") fn_commits_dump "$@" ;;
  "test") fn_test "$@" ;;
esac
