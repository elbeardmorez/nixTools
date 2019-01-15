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
\nwhere <OPTION> can be:\n
  help  : print this text
  diff  : output diff to stdout
  log<TYPE> [N] [ID]  : print log entries\n
    <TYPE>
      ''  :  simple log format
      1   :  single line log format
      x   :  extended log format
    [N]  : limit the number of results
    [ID]  : return results back starting from an id or partial
            description string. implies N=1 unless N specified\n
  sha <ID> [N] [LOGTYPE]  : return commit sha / description for an id
                            or partial description string. use N to
                            limit the search range to the last N
                            commits. use LOGTYPE to switch output
                            format type as per the options above
  st|status      : show column format status with untracked local
                   path files only
  sta|status-all : show column format status
  addnws  : add all files, ignoring white-space changes
  fp|format-patch <ID> [N]  : format N patch(es) back from an id or
                              partial description string
  rb|rebase <ID> [N]  : interactively rebase back from id or partial
                        description string. use N to limit the search
                        range to the last N commits
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
  [ $# -lt 1 ] && echo "[error] id arg missing" 1>&2 && return 1
  id="$1" && shift
  commit="$(git log -n1 --oneline $id 2>/dev/null)"
  if [ $? -ne 0 ]; then
    commit="$(fnCommitByName "$id" "$@")"
    res=$?; [ $res -ne 0 ] && return $res
  fi
  echo "$commit"
  return 0
}

fnCommitByName() {
  [ $# -lt 1 ] && echo "[error] search arg missing" 1>&2 && return 1
  declare -a binargs
  declare -a cmdargs
  cmdargs=("--oneline")
  limit=1
  while [ -n "$1" ]; do
    case "$1" in
      "nolimit") limit=-1 ;;
      "colours") binargs=("-c" "color.ui=always") ;;
      *)
        if [ "x$(echo "$1" | sed -n '/^[0-9-]\+$/p')" != "x" ]; then
          cmdargs=("${cmdargs[@]}" "-n" $1)
        elif [ -z $search ]; then
          search="$1"
        else
          echo "[info] unknown arg '$1', ignoring" 1>&2
        fi
        ;;
     esac
     shift
  done
  commits="$(git "${binargs[@]}" log "${cmdargs[@]}" | grep "$search")"
  IFS=$'\n'; arr_commits=($(echo -e "$commits")); IFS="$IFSORIG";
  [ ${#arr_commits[@]} -eq 0 ] &&
    echo "[info] no commits found matching search '$search'" 1>&2 && return 1
  [[ ${#arr_commits[@]} -gt 1 && limit -eq 1 ]] &&
    echo "[info] multiple commits matching search '$search'" \
         "found. try a more specific search string, else use" \
         "the [N] argument to limit the commit range" 1>&2 && return 1
  [ $limit -eq -1 ] && limit=${#arr_commits[@]}
  echo -e "$commits" | tail -n $limit
  return 0
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

fnLog() {
  command="$1" && shift
  c_br="\e[0;33m"
  c_off="\e[m"
  count=-1
  search=""
  declare -a binargs
  declare -a cmdargs
  binargs=("-c" "color.ui=always")
  while [ -n "$1" ]; do
    [ "x$(echo "$1" | sed -n '/^[0-9]\+$/p')" != "x" ] && count=$1 && shift && continue
    [ "x$(echo "$1" | sed -n '/^[^-]\+/p')" != "x" ] && search=$1 && shift && continue
    [ "x$1" = "x--" ] && cmdargs=("${cmdargs[@]}" "$@") && break
    cmdargs[${#cmdargs[@]}]="$1"
    shift
  done
  [ $count -gt 0 ] && cmdargs=("-n" $count "${cmdargs[@]}")
  if [ -n "$search" ]; then
    commit=$(fnCommit "$search")
    res=$?; [ $res -ne 0 ] && exit $res
    cmdargs[${#cmdargs[@]}]="$(echo "$commit" | cut -d' ' -f1)"
  fi
  if [ "x$command" = "xlog" ]; then
    git "${binargs[@]}" log --format=format:"%at | %ct | version: $c_br%H$c_off%n %s (%an)" "${cmdargs[@]}" | awk '{for(l=1; l<=3; l++) {if ($l~/[0-9]+/) {$l=strftime("%Y%b%d %H:%M:%S",$l);}}; print $0}' | xargs -0 echo -e | sed '$d'
  else
    format="$([ "x$command" = "xlog1" ] && echo "oneline" || echo "fuller")"
    git "${binargs[@]}" log --format="$format" "${cmdargs[@]}" | cat
  fi
}

fnProcess() {
  command="help" && [ $# -gt 0 ] && command="$1" && shift
  case "$command" in
    "help") help ;;
    "diff") git diff $@ ;;
    "log"|"logx"|"log1")
      fnLog $command "$@"
      ;;
    "sha")
      [ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
      declare -a cmdargs
      cmdargs=("nolimit")
      log=""
      while [ -n "$1" ]; do
        case "$1" in
          "log"|"log1"|"logx") log="$1" ;;
          *) cmdargs[${#cmdargs[@]}]="$1" ;;
        esac
        shift
      done
      [ -z $log ] && cmdargs[${#cmdargs[@]}]="colours"
      commits=$(fnCommit "${cmdargs[@]}")
      res=$?; [ $res -ne 0 ] && exit $res
      if [ -z $log ]; then
        echo -e "$commits"
      else
        IFS=$'\n'; arr_commits=($(echo -e "$commits")); IFS="$IFSORIG"
        for c in "${arr_commits[@]}"; do
          fnLog $log 1 "$(echo "$c" | cut -d' ' -f1)"
          [ "x$log" = "xlogx" ] && echo
        done
      fi
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
      echo "[info] git: adding all files, ignoring white-space changes"
      git diff --ignore-all-space --no-color --unified=0 "$@" | git apply --cached --ignore-whitespace --unidiff-zero
      ;;
    "fp"|"formatpatch"|"format-patch")
      [ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
      id="$1" && shift
      n=1 && [ $# -gt 0 ] && n="$1" && shift
      [ "x`echo "$n" | sed -n '/^[0-9]\+$/p'`" = "x" ] && echo "[error] invalid number of patches: '$n'" && exit 1
      commit=$(fnCommit "$id")
      res=$?; [ $res -ne 0 ] && exit $res
      sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
      echo "[info] formatting patch for rebasing from commit '$commit'"
      git format-patch -k -$n $sha
      ;;
    "rb"|"rebase")
      [ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
      commit=$(fnCommit "$@")
      res=$?; [ $res -ne 0 ] && return $res
      sha="`echo $commit | sed -n 's/\([^ ]*\).*/\1/p'`"
      # ensure parent exists, else assume root
      git rev-parse --verify "$sha^1"
      root=$([ $? -ne 0 ] && echo 1 || echo 0)
      echo "rebasing from commit '$commit'"
      [ $root -eq 1 ] && git rebase -i --root || git rebase -i $sha~1
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
      [ "x$target" = "xHEAD" ] && target=`git status | sed -n "s/.* branch '\([^']\{1,\}\)' on '[0-9a-z]\{1,\}'.*/\1/p"`
      sha_current=`git log --oneline -n1 | cut -d' ' -f1`
      sha_target=`git log --oneline $target | grep $sha_current -B $num | head -n1 | cut -d' ' -f1`
      echo -n "[info] fast-forwarding $num commits, '$sha_current' -> '$sha_target' on branch '$target', ok? [y/n]: "
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
