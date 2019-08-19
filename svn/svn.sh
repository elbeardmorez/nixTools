#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

SERVER=http://localhost/svn/
REPO_OWNER_ID=80
RX_AUTHOR="${RX_AUTHOR:-""}"

help() {
  echo -e "SYNTAX: $SCRIPTNAME OPTION [OPT_ARGS]
\nwhere OPTION:
  -l|--log [r]X [[r]X2]  : output commit log info for items / revision
                           described, with X a revision number, or the
                           limit of commits to output
\n    with supported X:
      [X : 1 <= X <= 25]   : last x commits (-l X)
      [X : X > 25]         : revision X (-c X)
      [+X : 1 <= X <= ..]  : revision X (-c X)
      [rX : 1 <= X <= ..]  : revision X (-c X)
      [-X : X <= -1]       : last X commits (-l X)
      [rX_1 rX_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision X_1 and revision X_2 inclusive
          (-r'min(X_1,X_2)'..'max(X_1,X_2)')
      [-X_1 -X_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision 'HEAD - X_1' and revision
          'HEAD - X_2' inclusive (-r'-min(X_1,X_2)'..-'max(X_1,X_2)')
\n  -am|--amend ID  : amend log entry for commit ID
  -cl|--clean TARGET  : remove all '.svn' under TARGET
  -ign|--ignore PATH [PATH ..]  : add a list of paths to svn:ignore
  -rev|--revision  : output current revision
  -st|--status  : display an improved status of updated and new files
  -d|--diff [ID]  : take diff of ID (default PREV) against HEAD
  -fp|--format-patch ID TARGET  : format a patch for revision ID and
                                  written to TARGET
  -ra|--repo-add  : add a new repository to the server using an
                    existing template named 'temp'
  -rc|--repo-clone SOURCE_URL TARGET  : clone remote repository at
                                        SOURCE_URL to local TARGET
                                        directory
"
}

fn_log() {
  # validate arg(s)
  rev1=-1 && [ $# -gt 0 ] && rev1="$1" && shift
  [ "x$(echo $rev1 | sed -n '/^[-+r]\?[0-9]\+$/p')" = "x" ] &&
    echo "[error] invalid revision arg '$rev1'" && return 1
  rev2="" && [ $# -gt 0 ] &&
    [ "x$(echo "$1" | sed -n '/^[-+r]\?[0-9]\+$/p')" != "x" ] &&
    rev2="$1" && shift

  # tokenise
  IFS=$'\n' && tokens=($(echo " $rev1 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p')) && IFS="$IFSORG"
  rev1prefix="$(echo ${tokens[0]} | tr -d ' ')"
  rev1="$(echo ${tokens[1]} | tr -d ' ')"
  rev1suffix="$(echo ${tokens[2]} | tr -d ' ')"
  tokens=("" "" "")
  [ "x$rev2" != "x" ] && \
    { IFS=$'\n' && tokens=($(echo " $rev2 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p')) && IFS="$IFSORG"; }
  rev2prefix="$(echo ${tokens[0]} | tr -d ' ')"
  rev2="$(echo ${tokens[1]} | tr -d ' ')"
  rev2suffix="$(echo ${tokens[2]} | tr -d ' ')"
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fn_log] rev1: '$rev1prefix|$rev1|$rev1suffix' $([ "x$rev2" != "x" ] && echo "rev2: '$rev2prefix|$rev2|$rev2suffix'")" 1>&2
  # mod
  if [ "x$rev1prefix" = "x" ]; then
    [ $rev1 -gt 25 ] && rev1prefix="-r " || rev1prefix="-"
  fi
  [[ "x$rev1prefix" == "x" && $rev1 -gt 25 ]] && rev1prefix="-"
  [ "x$rev1prefix" = "x+" ] && rev1prefix="-r "
  [ "x$rev1prefix" = "xr" ] && rev1prefix="-r "
  if [ "x$rev2" != "x" ]; then
    rev1suffix=":"
    [[ "x$rev1prefix" != "x-" && $rev1 -gt $rev2 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    [[ "x$rev1prefix" == "x-" && $rev2 -gt $rev1 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    rev2prefix=""
  fi
  if [ "x$rev2" = "x" ]; then
    [[ "x$rev1prefix" == "x-" || "x$rev1prefix" == "x" ]] && rev1prefix="-l "
  else
    if [ "x$rev1prefix" = "x-" ]; then
      # convert to revision numbers
      base=$(fn_revision)
      [ "x$base" = "x" ] && base=0
      rev2prefix=""
      rev1=$((base - rev1 + 1))
      rev2=$((base - rev2 + 1))
    fi
    rev1prefix="-r "
  fi
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fn_log] rev1: '$rev1prefix|$rev1|$rev1suffix' $([ "x$rev2" != "x" ] && echo "rev2: '$rev2prefix|$rev2|$rev2suffix'")" 1>&2
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fn_log] svn log $rev1prefix$rev1$rev1suffix$rev2prefix$rev2$rev2suffix" "$@" 1>&2
  [ $TEST -eq 0 ] && svn log $rev1prefix$rev1$rev1suffix$rev2prefix$rev2$rev2suffix "$@"
}

fn_amend() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  revision=$1 && shift
  svn propedit --revprop -r $revision svn:log
}

fn_clean() {
  target="$1"
  [ ! -d "$target" ] && \
    echo "[error] target '$target' is not a writable directory" 1>&2 && return 1

  IFS=$'\n'; matches=($(find $target -name *.svn)); IFS="$IFSORG"
  if [ ${#matches[@]} -eq 0 ]; then
    echo "[info] no '.svn' directories found under specified target"
  else
    echo "[info] ${#matches[@]} '.svn' director$([ ${matches[@]} -eq 1 ] && echo "y" || echo "ies") found under specified target"
    [ $DEBUG -gt 0 ] && \
      for d in ${matches[@]}; do echo "$d"; done
    if [ $(fn_decision "[user] remove all?" 1>/dev/null) ]; then
      removed=0
      for d in ${matches[@]}; do
        rm -rf "$d"
        [[ $? -eq 0 && ! -d $d ]] && \
          count=$((removed + 1)) || \
          echo "[info] failed to remove '$d'"
      done
      echo "[info] removed $removed '.svn' director$([ ${matches[@]} -eq 1 ] && echo "y" || echo "ies")"
    fi
  fi
}

fn_ignore() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" && exit 1

  [ ! -d $(pwd)/.svn ] && \
    echo "[error] target '$(pwd)' is not under source control" 1>&2 && return 1

  declare list
  for arg in "$@"; do
    if [ ${#list} -eq 0 ]; then
      list="$arg"
    else
      list=$list\$\'\\n\'$arg
    fi
  done
  eval "svn propset svn:ignore $list ."

  sleep 1
  echo "[info] svn:ignore set:"
  svn propget svn:ignore
}

fn_revision() {
  echo "$(svn info 2>/dev/null)" | sed -n 's/^\s*Revision:\s*\([0-9]\+\)\s*/\1/p'
}

fn_status() {
  svn status --show-updates "$@" | grep -vP "\s*\?"
}

fn_diff() {
  svn diff -c${1:-"-1"}
}

fn_patch() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
  target="" && [ $# -gt 0 ] && target="$1" && shift
  l=1;
  loglines=()

  while read -r line; do loglines[${#loglines[@]}]="$line"; done << EOF
"$(fn_log $revision 2>/dev/null)"
EOF
  [ $DEBUG -gt 0 ] && echo "[debug|fn_patch] dumping commit message:" &&
    for l in $(seq 0 1 ${#loglines[@]}); do echo "idx$l: ${loglines[$l]}"; done

  revision="$(echo "${loglines[1]}" | cut -d'|' -f1 | sed 's/\s*r\([0-9]*\)\s*/\1/')"
  author="$(echo "${loglines[1]}" | cut -d'|' -f2 | sed 's/\(^\s*\|\s*$\)//g' | sed "$RX_AUTHOR")"
  date_="$(echo "${loglines[1]}" | cut -d'|' -f3 | sed 's/\(^\s*\|\s*$\)//g' | cut -d' ' -f1-3)"
  if [ "x$target" = "x" ]; then
    target="$(echo "${loglines[3]}" | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/\1\2/;s/ /./g;s/^\.//g' | sed 's/^[-.*]*\.//g' | sed 's/[/\`]/./g' | sed 's/\.\././g' | awk '{print tolower($0)}')"
    target="$([ $revision -eq -1 ] && echo "0001" || echo "$revision").$target.diff"
  fi
  message="author: $author\ndate: $date_\nrevision: $revision\nsubject: "
  for l in $(seq 3 1 $[${#loglines[@]} - 2]); do
     message+="${loglines[$l]}\n"
  done
  echo -e "$message\n" > "$target"
  fn_diff $revision >> "$target"
}

fn_repo_add() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  target="$1"
  if [ "$(echo "$target" | awk '{print substr($0, length($0))}')" = "/" ]; then
    target=$(echo "$target" | awk '{print substr($0, 1, length($0) - 1)}')
  fi

  [ -e "$target" ] || mkdir -p "$target"
  [ ! -d "$target" ] && \
    echo "[error] target '$target' is not a writable directory" 1>&2 && return 1
  [ -n "$(ls -1 "$target")" ] &&
    { fn_decision "[user] target path for repo is not empty, delete contents?" 1>/dev/null || return 1; }
  repo=$(echo "$target" | sed 's/.*\/\(.*\)/\1/')

  # cd necessary as svnadmin doesn't handle relative paths
  cwd="$(pwd)"
  cd "$target"
  svnadmin create --fs-type fsfs "$target"
  chown -R $REPO_OWNER_ID:$REPO_OWNER_ID "$target"
  chmod -R ug+rw "$target"

  rm -rf temp
  svn co $SERVER$repo temp
  svn mkdir temp/branches temp/tags temp/trunk
  svn ci -m "[add] repository structure" ./temp
  rm -rf temp
}

fn_repo_clone() {
  [ $# -lt 1 ] && help && echo "[error] insufficient args" 1>&2 && return 1
  source="$1" && shift
  target="$1" && shift
  [ ! -d "$target" ] && mkdir -p "$target"
  target="$(cd $target; pwd)"
  svnadmin create "$target"
  echo -e '#!/bin/sh\nexit 0' > "${target}/hooks/pre-revprop-change"
  chmod 755 "${target}/hooks/pre-revprop-change"
  svnsync init "file://$target" "$source" || exit 1
  svnsync sync "file://$target" || exit 1
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
      echo ">log 30" && fn_log 30
      echo ">log -30" && fn_log -30
      echo ">log +10" && fn_log +10
      echo ">log r10" && fn_log r10
      echo ">log r10 /path" && fn_log r10 /path
      echo ">log r10 r15 /path" && fn_log r10 r15 /path
      ;;
    *)
      help && echo "[error] unsupported test name '$type'" 1>&2
      return 1
      ;;
  esac
}

fn_process() {
  option="help"
  [ $# -gt 0 ] && s="$(echo "$1" | sed 's/[ ]*-*//')" && shift
  [ -n "$(echo "$s" | sed -n '/\(h\|help\|l\|log\|am\|amend\|cl\|clean\|ign\|ignore\|rev\|revision\|d\|diff\|st\|status\|fp\|patch\|formatpatch\|format-patch\|ra\|repo-add\|rc\|repo-clone\|test\)/p')" ] && option="$s"
  case "$option" in
    "h"|"help") help ;;
    "l"|"log") fn_log "$@" ;;
    "am"|"amend") fn_amend "$@" ;;
    "cl"|"clean") fn_clean "$@" ;;
    "ign"|"ignore") fn_ignore "$@" ;;
    "rev"|"revision") fn_revision ;;
    "st"|"status") fn_status "$@" ;;
    "d"|"diff") fn_diff "$@" ;;
    "fp"|"patch"|"formatpatch"|"format-patch") fn_patch "$@" ;;
    "ra"|"repo-add") fn_repo_add "$@" ;;
    "rc"|"repo-clone") fn_repo_clone "$@" ;;
    "test") fn_test "$@" ;;
    *) help && echo "[error] unsupported option '$option'" 1>&2 && exit ;;
  esac
}

fn_process "$@"
