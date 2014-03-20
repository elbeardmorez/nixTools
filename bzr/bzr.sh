#!/bin/sh

maxmessagelength=100

command=log && [ $# -gt 0 ] && command="$1" && shift
case "$command" in
  "diff") bzr diff -c${1:-"-1"} ;;
  "log")
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
    ;;
  "patch"|"formatpatch"|"format-patch")
    revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
    target=""
    if [ $# -gt 0 ]; then
      target="$1" && shift
    else
      target=$(bzr.sh log $revision | sed -n '/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/\1\2/;s/ /./g;s/^\.//g' | sed 's/^[-.*]*\.//g' | sed 's/[/`]/./g' | sed 's/\.\././g' | awk '{print tolower($0)}')
      target="$([ $revision -eq -1 ] && echo "0001" || echo "$revision").${target:0:maxmessagelength}.diff"
    fi
    bzr log -c$revision | sed 's/^/#/' > $target
    bzr.sh diff $revision >> $target
    ;;
  "commits")
    search="$1" && shift
    search_type="message"
    [ $# -gt 0 ] && search_type="$1"
    bzr log --match-$search_type=".*$search.*" | sed -n '/^revno:.*/,/^-\+$/{/^revno:.*/{s/^revno: \([0-9]\+\)/\1|/;H;b};/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H}};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/r\1\2/;s/ /./g' | awk '{print tolower($0)}'
    ;;
  "commits-dump")
    target="$1" && shift
    echo "target: '$target'"
    [ ! -d "$target" ] && mkdir -p "$target" 2>/dev/null
    commits=($(bzr.sh commits $1))
    for c in "${commits[@]}"; do
      revision="${c%%|*}"
      message="${c:$[${#revision}+1]:maxmessagelength}"
      file=${revision}.${message}.diff
      echo "revision: '$revision', file: '$file'"
      bzr.sh format-patch "${revision#r}" "$target/$file"
    done
    ;;
esac
