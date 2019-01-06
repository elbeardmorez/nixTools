#!/bin/sh

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}
IFSORIG="$IFS"

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  setopt KSH_ARRAYS
fi

help() {
  echo -e "USAGE: $SCRIPTNAME <command> [command-args}

where <command> is:

  help  : print this text
  diff  : output diff to stdout
  log [n]   : print last n log entries, simple log format
  log1 [n]  : print last n log entries, single line log format
  logx [n]  : print last n log entries, extended log format
  st|status : show status with untracked in column format
  addnws  : add all files, ignoring white-space changes
  fp|formatpatch <ID> [n]  : format n patch(es) by commit / description
  rb|rebase <ID>  : interactively rebase by commit / description
  cl|clone <REPO>  : clone repo
  co|checkout      : checkout files / branches
  ca|commitamend         : commit, amending previous
  can|commitamendnoedit  : commit, amending previous without editing message
  ac|addcommit               : add updated and commit
  aca|addcommitamend         : add updated and commit, amending previous
  acan|addcommitamendnoedit  : add updated and commit, amending previous without editing message
  ff|fast-forward  : identify current 'branch' and fast-forward to HEAD of 'linked'
"
}

fnCommit() {
  [ $# -lt 1 ] && echo "[fnCommit] id arg missing" && exit
  id="$1" && shift
  cmd_sha="git log -n1 --oneline $id"
  $cmd_sha > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    sha=`$cmd_sha | cut -d' ' -f1`
  else
    sha=`fnCommitByName "$id"`
  fi
  echo "$sha"
}

fnCommitByName() {
  [ $# -lt 1 ] && echo "[fnCommitByName] search arg missing" && exit
  search="$1" && shift
  last=50 && [ $# -gt 0 ] && last=$1 && shift
  IFS=$'\n'; commits=(`git log -n$last --oneline | grep "$search"`); IFS="$IFSORIG"
  [[ ${#commits[@]} -ne 1 || "${commits[0]}" == "" ]] &&
    echo "be more precise in your search string or up the 'search last' arg" 1>&2 && exit
  commit="${commits[0]}"
  echo "$commit"
}

fnDecision() {
  while [ 1 -eq 1 ]; do
    read "${CMDARGS_READ_SINGLECHAR[@]}"
    case "$REPLY" in
      "y"|"Y") echo "$REPLY" 1>&2; echo 1; break ;;
      "n"|"N") echo "$REPLY" 1>&2; echo 0; break ;;
    esac
  done
}

fnProcess() {
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
    "st"|"status")
      git status --col
      ;;
    "addnws")
      echo "git: adding all files, ignoring white-space changes"
      git diff --ignore-all-space --no-color --unified=0 "$@" | git apply --cached --ignore-whitespace --unidiff-zero
      ;;
    "fp"|"formatpatch"|"format-patch")
      [ $# -lt 1 ] && echo "[error] not enough args" && exit
      id="$1" && shift
      n=1 && [ $# -gt 0 ] && n="$1" && shift
      [ "x`echo "$n" | sed -n '/^[0-9]\+$/p'`" == "x" ] && echo "invalid number of patches: '$n'" && exit 1
      commit=`fnCommit "$id"`
      if [ "x$commit" != "x" ]; then
        sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
        echo "formatting patch for rebasing from commit '$commit'"
        git format-patch -k -$n $sha
      fi
      ;;
    "rb"|"rebase")
      [ $# -lt 1 ] && echo "[error] not enough args" && exit
      commit=`fnCommit "$@"`
      if [ "x$commit" != "x" ]; then
        sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
        # ensure parent exists, else assume root
        git rev-parse --verify "$sha^1"
        root=$([ $? -ne 0 ] && echo 1 || echo 0)
        echo "rebasing from commit '$commit'"
        [ $root -eq 1 ] && git rebase -i --root || git rebase -i $sha~1
      fi
      ;;
    "co"|"checkout")
      git checkout "$@"
      ;;
    "cl"|"clone")
      git clone "$@"
      ;;
    "ca"|"commitamend")
      git commit --amend "$@"
      ;;
    "can"|"commitamendnoedit")
      git commit --amend --no-edit "$@"
      ;;
    "ac"|"addcommit")
      git add -u .
      git commit
      ;;
    "aca"|"addcommitamend")
      git add -u .
      git commit --amend
      ;;
    "acan"|"addcommitamendnoedit")
      git add -u .
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
        read "${CMDARGS_READ_SINGLECHAR[@]}"
        case "$REPLY" in
          "y"|"Y") echo "$REPLY" 1>&2; retry=0; git checkout $sha_target ;;
          "n"|"N") echo "$REPLY" 1>&2; exit 0 ;;
        esac
      done
      ;;
    "rd"|"rescue-dangling")
      IFS=$'\n'; commits=($(git fsck --no-reflog | awk '/dangling commit/ {print $3}')); IFS="$IFSORG"
      if [ ${#commits[@]} -eq 0 ]; then
        echo "[info] no dangling commits found in repo"
      else
        echo -n "[info] rescue ${#commits[@]} dangling commit$([ ${#commits[@]} -ne 1 ] && echo "s") found in repo? [y/n]: "
        res=$(fnDecision)
        [ "x$res" = "x1" ] && \
          mkdir commits && \
          for c in ${commits[@]}; do git log -n1 -p $c > commits/$c.diff; done
      fi
      ;;
    *)
      git $command "$@"
      ;;
  esac
}

fnSourced() {
  # support for being 'sourced' limited to bash and zsh
  [ $DEBUG -gt 0 ] && echo "[info] \$0: '$0', ZSH_VERSION: '$ZSH_VERSION', ZSH_EVAL_CONTEXT: '$ZSH_EVAL_CONTEXT', BASH_VERSION: '$BASH_VERSION', BASH_SOURCE[0]: '${BASH_SOURCE[0]}'" 1>&2
  [ -n "$BASH_VERSION" ] && ([[ "${0##*/}" == "${BASH_SOURCE##*/}" ]] &&  echo 0 || echo 1) && return
  [ -n "$ZSH_VERSION" ] && ([[ "$ZSH_EVAL_CONTEXT" =~ ":file" ]] && echo 1 || echo 0) && return
  echo 0
}

[ $(fnSourced) -eq 0 ] && fnProcess "$@"
