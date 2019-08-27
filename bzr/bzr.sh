#!/bin/sh
SCRIPTNAME=${0##*/}
IFSORG="$IFS"

DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

RX_AUTHOR="${RX_AUTHOR:-""}"
RX_DESCRIPTION_DEFAULT='s/^[ ]*\(.\{20\}[^.]*\).*$/\1/'
RX_DESCRIPTION="${RX_DESCRIPTION:-"$RX_DESCRIPTION_DEFAULT"}"

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION]
\nwith OPTION:
\n  -l|--log [r]X [[r]X2]  : output log information for commit(s) X:
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
\n  -d|--diff [REVISION]  : show diff of REVISION again previous
                          (default: HEAD)
  -p|--patch [REVISION] [TARGET]  : format REVISION (default: HEAD)
                                    as a diff patch file with
                                    additional context information
                                    inserted as a header to TARGET
                                    (default: auto-generated from
                                    commit message)
  -c|--commits [SEARCH] [TYPE]  : search log for commits containing
                                  SEARCH. in TYPE field
\n    with support TYPE:
      message  : search the message content (default)
      author  : search the author field
      committer  : search the commiter field
\n  -dc|--dump-commits TARGET [SEARCH] [TYPE]
    : wrapper for 'commits' which also dumps any matched commits
      to TARGET
"
}

fn_log() {
  # validate arg(s)
  rev1=-1 && [ $# -gt 0 ] && rev1="$1" && shift
  [ "x$(echo $rev1 | sed -n '/^[-+r]\?[0-9]\+$/p')" = "x" ] &&
    echo "[error] invalid revision arg '$rev1'" && exit 1
  rev2="" && [ $# -gt 0 ] && rev2="$1" && shift
  [ "x$rev2" != "x" ] && [ "x$(echo $rev2 | sed -n '/^[-+r]\?[0-9]\+$/p')" = "x" ] &&
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
  [ "x$rev1prefix" = "x+" ] && rev1prefix=""
  [ "x$rev1prefix" = "xr" ] && rev1prefix=""
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

fn_info() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  revision="$1"
  commit="$(bzr log -r$revision | sed -n '${x;s/\n/\\n/g;s/\(\\n  \)/\\n/g;s/^.*\\nrevno: \([0-9]\+\)\\n\(author\|committer\): \([^>]\+>\)\\n.*branch[^:]*: \(.\+\)\\ntimestamp: \(.\+\)\\nmessage:\(\\n\)*[\t ]*\(.*\)$/\5|r\1|\3|\4|\7/;s/\(\\n\)*$//;p;b;};H;')"
  echo -E "$(date -d "${commit%%|*}" "+%s")|${commit#*|}"
}

fn_diff() {
  declare revision; revision="${1:-"-1"}"
  bzr diff -c${revision#r}
}

fn_patch_name() {
  declare description; description="$1" && shift
  declare name

  # construct name
  name="$description"
  # replace whitespace and special characters
  name="$(echo "$name" | sed 's/[ ]/./g;s/[\/:]/_/g')"
  # strip any prefix garbage
  name="$(echo "$name" | sed 's/^\[PATCH[^]]*\][. ]*//;s/\n//;')"
  # lower case
  name="$(echo "$name" | awk '{print tolower($0)}').diff"

  [ $DEBUG -ge 5 ] && echo "[debug] description: '$description' -> name: '$name'" 1>&2
  echo "$name"
}

fn_patch() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  declare revision; revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
  declare target; target="" && [ $# -gt 0 ] && target="$1" && shift
  declare info; info="$(fn_info $revision)"
  declare parts; IFS="|"; parts=($(echo "$info")); IFS="$IFSORG"; IFS="$IFSORG"
  declare dt; dt="$(date -d"@${parts[0]}" "+%a %d %b %Y %T %z")"
  revision="${parts[1]}"
  declare author; author="$(echo "${parts[2]}" | sed "$RX_AUTHOR")"
  declare branch; branch="$(echo "${parts[3]}" | sed "$RX_AUTHOR")"
  declare message; message="${parts[4]}"
  declare description; description="$(echo "$message" | sed "$RX_DESCRIPTION")"
  declare comments; comments="$(echo -E "${message:${#description}}" | sed 's/^[. ]*\(\\n\)*//;s/\(\\n\)*$//')"
  declare header; header="Author: $author\nDate: $dt\nRevision: $revision\nBranch: $branch\nSubject: $description$([ -n "$comments" ] && echo "\n\n$comments")"

  if [ -d "$target" ]; then
    target="$(echo "$target" | sed 's/\/*$/\//')$(fn_patch_name "$description")"
  elif [ -z "$target" ]; then
    target="$(fn_patch_name "$description")"
  fi

  echo -e "$header\n" > "$target"
  fn_diff $revision >> "$target"
}

fn_commits() {
  declare search; search="$1" && shift
  declare search_type; search_type="message"
  [ $# -gt 0 ] && search_type="$1"
  bzr log --match-$search_type=".*$search.*" | sed -n '/^revno:.*/,/^-\+$/{/^revno:.*/{s/^revno: \([0-9]\+\)/\1|/;H;b};/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H}};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/r\1\2/;s/ /./g' | awk '{print tolower($0)}'
}

fn_dump_commits() {
  declare target; target="$1" && shift
  declare -a commits
  declare commit
  declare revision
  declare message
  declare file
  [ ! -d "$target" ] && mkdir -p "$target" 2>/dev/null
  IFS=$'\n'; commits=($(fn_commits "$@")); IFS="$IFSORG"
  echo "[info] dumping ${#commits[@]} commit$([ ${#commits[@]} -ne 1 ] && echo "s") to target '$target'"
  for commit in "${commits[@]}"; do
    revision="${commit%%|*}"
    fn_patch "${revision#r}" "$target"
  done
}

fn_test() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  type="$1" && shift
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
    "info"|"patch_name"|"patch")
      fn_$type "$@"
      ;;
    *)
      help && echo "[error] unsupported test name '$type'" 1>&2
      return 1
      ;;
  esac
}

fn_process() {
  declare option; option="help"
  [ $# -gt 0 ] && option="$(echo "$1" | sed 's/[ ]*-*//')" && shift
  case "$option" in
    "h"|"help") help ;;
    "l"|"log") fn_log "$@" ;;
    "d"|"diff") fn_diff "$@" ;;
    "p"|"patch"|"formatpatch"|"format-patch") fn_patch "$@" ;;
    "c"|"commits") fn_commits "$@" ;;
    "dc"|"dump-commits") fn_dump_commits "$@" ;;
    "test") fn_test "$@" ;;
    *) help && echo "[error] unsupported option '$option'" 1>&2 && exit ;;
  esac
}

fn_process "$@"
