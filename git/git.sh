#!/bin/bash

IFSORIG="$IFS"

function fnCommitByName {
  [ $# -lt 1 ] && echo "[fnCommitByName] search arg missing" && exit
  search="$1" && shift
  last=50 && [ $# -gt 0 ] && last=$1 && shift
  IFS=$'\n'; commits=(`git log -n$last --oneline | grep "$search"`); IFS="$IFSORIG"
  [[ ${#commits[@]} -ne 1 || ${commits[0]} == "" ]] &&
    echo "be more precise in your search string or up the 'search last' arg" 1>&2 && exit
  commit="${commits[0]}"
  echo "$commit"
}

function help {
  echo -e "USAGE: _git <command> [command-args}

where <command> is:

  help      : print this text
  diff      : output diff to stdout
  log [n]   : print last n log entries, simple log format
  log1 [n]  : print last n log entries, single line log format
  logx [n]  : print last n log entries, extended log format
  addws     : add all files, ignoring white-space changes
  addb      : add all files, ignoring space changes
  fp|formatpatch <ID> [n] : format n patch(es) by commit description
  rb|rebase <ID>          : interactively rebase by commit description
  cl|clone <REPO>         : clone repo
  co|checkout             : checkout files / branches
  c|commit                : add updated and commit
  ca|commitamend          : add updated and commit, amending last commit
  a|amend                 : amend previous commit
  an|amendnoedit          : amend previous commit without editing commit message
  ff|fast-forward         : identify current 'branch' and fast-forward to HEAD of 'linked'
"
}

function process {
  command="help" && [ $# -gt 0 ] && command="$1" && shift
  case "$command" in
    "help") help ;;
    "diff") TERM=linux git diff $@ ;;
    "log"|"logx"|"log1")
      count=1 && [ $# -gt 0 ] && count=$1 && shift
      [ $count == "all" ] && count=$(git log --format=oneline | wc -l)
      if [ "x$command" == "xlog" ]; then
        TERM=linux git log -n $count --format=format:"%at | %ct | version: %H%n %s (%an)" "$@" | awk '{for(l=1; l<=3; l++) {if ($l~/[0-9]+/) {$l=strftime("%Y%b%d",$l);}}; print $0}'
      else
        format="fuller" && [ "x$command" == "xlog1" ] && format="oneline"
        TERM=linux git log --format="$format" -n $count "$@" | cat
      fi
      ;;
    "addws")
      echo "git: adding all files, ignoring white-space changes"
      git diff --ignore-all-space --no-color | git apply --cached --ignore-whitespace
      ;;
    "addb") echo "git: adding all files, ignoring space changes";
      git diff --ignore-all-space --no-color | git apply --cached --ignore-space-change
      ;;
    "fp"|"formatpatch"|"format-patch")
      [ $# -lt 1 ] && echo "[error] not enough args" && exit
      id="$1" && shift
      n=1 && [ $# -gt 0 ] && n="$1" && shift
      [ "x`echo "$n" | sed -n '/^[0-9]\+$/p'`" == "x" ] && echo "invalid number of patches: '$n'" && exit 1
      commit=`fnCommitByName "$id"`
      if [ "x$commit" != "x" ]; then
        sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
        echo "formatting patch for rebasing from commit '$commit'"
        git format-patch -k -$n $sha
      fi
      ;;
    "rb"|"rebase")
      [ $# -lt 1 ] && echo "[error] not enough args" && exit
      commit=`fnCommitByName "$@"`
      if [ "x$commit" != "x" ]; then
        sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
        echo "rebasing from commit '$commit'"
        git rebase -i $sha~1
      fi
      ;;
    "co"|"checkout")
      git checkout "$@"
      ;;
    "cl"|"clone")
      git clone "$@"
      ;;
    "c"|"commit")
      git add -u .
      git commit
      ;;
    "ca"|"commit")
      git add -u .
      git commit --amend
      ;;
    "a"|"amend")
      git commit --amend "$@"
      ;;
    "an"|"amendnoedit")
      git commit --amend --no-edit "$@"
      ;;
    "ff"|"fast-forward")
      num=$1 && shift;
      target=`git rev-parse --abbrev-ref HEAD`
      [ "x$target" == "xHEAD" ] && target=`git status | sed -n "s/.* branch '\([^']\{1,\}\)' on '[0-9a-z]\{1,\}'.*/\1/p"`
      sha_current=`git log --oneline -n1 | cut -d' ' -f1`
      sha_target=`git log --oneline $target | grep $sha_current -B $num | head -n1 | cut -d' ' -f1`
      echo -n "fast-forwarding $num commits, '$sha_current' -> '$sha_target' on branch '$target', ok? [y/n]: "
      retry=1
      while [ $retry -gt 0 ]; do
        result=
        read -s -n 1 result
        case "$result" in
          "y"|"Y") echo "$result" 1>&2; retry=0; git checkout $sha_target ;;
          "n"|"N") echo "$result" 1>&2; exit 0 ;;
        esac
      done
      ;;
  esac
}

[ "${0##*/}" = "${BASH_SOURCE##*/}" ] && process $@
