#!/bin/sh

maxmessagelength=100

function help() {
  echo 'SYNTAX: bzr.sh [OPTION]
  with OPTION:
    log X  : output log information for commit(s) X:
      with X as:
        1 - 9 or -1 - -*  : last x commits
       +1 - +9            : revisions 1 - 9
       10 - *             : revisions 10 - *
'
}

function fnLog() {
  rev=-1 && [ $# -gt 0 ] && rev="$1" && shift
  [ "x$(echo $rev | sed -n '/^[-+]\?[0-9]\+$/p')" = "x" ] &&
    echo "[error] invalid revision(s) arg '$rev'" && exit 1
  rev2="" && [ $# -gt 0 ] && rev2="$1" && shift
  [ "x$rev2" != "x" ] && [ "x$(echo $rev | sed -n '/^[-+]\?[0-9]\+$/p')" = "x" ] &&
    echo "[error] invalid revision(s) arg '$rev2'" && exit 1
  [[ "x$rev" == "x${rev#+}" && $rev -gt 0 && $rev -lt 10 ]] && rev="-$rev.."
  rev=${rev#+}

  [ "x$rev2" != "x" ] && rev2="${rev2#+}" && rev2="${rev2#-}"
  echo bzr log -r$rev$rev2
  bzr log -r$rev$rev2
}

function fnDiff() {
  bzr diff -c${1:-"-1"}
}

function fnPatch() {
  revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
  target=""
  if [ $# -gt 0 ]; then
    target="$1" && shift
  else
    target=$(fnLog $revision | sed -n '/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/\1\2/;s/ /./g;s/^\.//g' | sed 's/^[-.*]*\.//g' | sed 's/[/`]/./g' | sed 's/\.\././g' | awk '{print tolower($0)}')
    target="$([ $revision -eq -1 ] && echo "0001" || echo "$revision").${target:0:maxmessagelength}.diff"
  fi
  bzr log -c$revision | sed 's/^/#/' > $target
  fnDiff $revision >> $target
}

function fnCommits() {
  search="$1" && shift
  search_type="message"
  [ $# -gt 0 ] && search_type="$1"
  bzr log --match-$search_type=".*$search.*" | sed -n '/^revno:.*/,/^-\+$/{/^revno:.*/{s/^revno: \([0-9]\+\)/\1|/;H;b};/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H}};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/r\1\2/;s/ /./g' | awk '{print tolower($0)}'
}

function fnCommitsDump() {
  target="$1" && shift
  echo "target: '$target'"
  [ ! -d "$target" ] && mkdir -p "$target" 2>/dev/null
  commits=($(fnCommits $1))
  for c in "${commits[@]}"; do
    revision="${c%%|*}"
    message="${c:$[${#revision}+1]:maxmessagelength}"
    file=${revision}.${message}.diff
    echo "revision: '$revision', file: '$file'"
    fnPatch "${revision#r}" "$target/$file"
  done
}

command=help && [ $# -gt 0 ] && command="$1" && shift
case "$command" in
  "help") help ;;
  "diff") fnDiff "$@" ;;
  "log") fnLog "$@" ;;
  "patch"|"formatpatch"|"format-patch") fnPatch "$@" ;;
  "commits") fnCommits "$@" ;;
  "commits-dump") fnCommitsDump "$@" ;;
esac
