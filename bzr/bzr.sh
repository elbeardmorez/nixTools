#!/bin/sh

maxmessagelength=100

command=log && [ $# -gt 0 ] && command="$1" && shift
case "$command" in
  "diff") bzr diff -c${1:-"-1"} ;;
  "log") bzr log $([ ${1:-"1"} -lt 100 ] && echo " -r-${1:-"1"}.." || echo " -c${1:-"-1"}") | cat ;;
  "patch"|"formatpatch"|"format-patch")
    revision=-1 && [ $# -gt 0 ] && revision="$1" && shift
    target=""
    if [ $# -gt 0 ]; then
      target="$1" && shift
    else
      target=$(bzr.sh log $revision | sed -n '/^message:.*/,/^-\+$/{/^message:.*/b;/^-\+$/{x;s/\(\s\+\|\n\)/ /g;p;s/.*//;x;b};H};${x;s/\(\s\+\|\n\)/ /g;p}' | sed 's/\s*\([0-9]\+|\)\s*\(.*\)/\1\2/;s/ /./g;s/^\.//g' | sed 's/^[-.*]*\.//g' | sed 's/[/`]/./g' | sed 's/.././g' | awk '{print tolower($0)}')
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
esac
