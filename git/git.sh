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
  echo -e "SYNTAX: $SCRIPTNAME <OPTION> [OPTION-ARGS]

where <OPTION> can be:

  help  : print this text
  diff  : output diff to stdout
  log [N]   : print last N log entries, simple log format
  log1 [N]  : print last N log entries, single line log format
  logx [N]  : print last N log entries, extended log format
  sha <SEARCH> [N]  : return full sha for an id or partial
                      description string. searching by description
                      is limited to the last N (default: 50) commits
  st|status      : show column format status with untracked local
                   path files only
  sta|status-all : show column format status
  addnws  : add all files, ignoring white-space changes
  fp|format-patch <ID> [N]  : format N patch(es) back from an id or
                              partial description string
  rb|rebase <SEARCH> [N]  : interactively rebase by id or partial
                            description string. searching by
                            description is limited to the last N
                            (default: 50) commits
  cl|clone <REPO>  : clone repo
  co|checkout      : checkout files / branches
  ca|commit-amend          : commit, amending previous
  can|commit-amend-noedit  : commit, amending previous without editing
                             message
  ac|add-commit                 : add updated and commit
  aca|add-commit-amend          : add updated and commit, amending
                                  previous commit message
  acan|add-commit-amend-noedit  : add updated and commit, amending
                                  previous without editing message
  ff|fast-forward  : identify current 'branch' and fast-forward to
                     HEAD of 'linked'
  rd|rescue-dangling  : dump any orphaned commits still accessable to
                        a 'commits' directory
"
}

fnCommit() {
  [ $# -lt 1 ] && echo "[fnCommit] id arg missing" && return 1
  id="$1" && shift
  commit="$(git log -n1 --oneline $id 2>/dev/null)"
  [ $? -ne 0 ] && commit="$(fnCommitByName "$id" "$@")"
  echo "$commit"
}

fnCommitByName() {
  [ $# -lt 1 ] && echo "[fnCommitByName] search arg missing" && return 1
  search="$1" && shift
  last=50 && [ $# -gt 0 ] && last=$1 && shift
  IFS=$'\n'; commits=(`git log -n$last --oneline | grep "$search"`); IFS="$IFSORIG"
  [[ ${#commits[@]} -ne 1 || "${commits[0]}" == "" ]] &&
    echo "be more precise in your search string or up the 'search last' arg" 1>&2 && return 1
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
    "sha")
      [ $# -lt 1 ] && echo "[error] not enough args" && exit
      commit=$(fnCommit "$@")
      [ -n "$commit" ] && echo "$commit"
      ;;
    "st"|"status")
      gitstatus=(git -c color.ui=always status)
      gitcolumn=(git column --mode=column --indent=$'\t')
      m="Untracked files:"
      # pre
      "${gitstatus[@]}" | sed -n '1,/^'"$m"'/{/^'"$m"'/{s/\(.*\):/\1 [local dir only]:/;N;N;p;b};p;}'
      # filtered
      "${gitstatus[@]}" | sed -n '/^'"$m"'/,/^*$/{/'"$m"'/{N;N;d;};/^$/{N;N;d;};/\//d;s/^[ \t]*//g;p;}' | "${gitcolumn[@]}"
      # post
      "${gitstatus[@]}" | sed -n '/^'"$m"'/,${/^'"$m"'/{N;N;d;};/^$/,${p;};}'
      ;;
    "sta"|"status-all")
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
    "ca"|"commit-amend")
      git commit --amend "$@"
      ;;
    "can"|"commit-amend-noedit")
      git commit --amend --no-edit "$@"
      ;;
    "ac"|"add-commit")
      git add -u .
      git commit
      ;;
    "aca"|"add-commit-amend")
      git add -u .
      git commit --amend
      ;;
    "acan"|"add-commit-amend-noedit")
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
      res=$(fnDecision)
      [ "x$res" = "x1" ] && \
        git checkout $sha_target
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
