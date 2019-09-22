#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}
IFSORG="$IFS"

declare term; [ -t 1 ] && term=1 || term=0

help() {
  echo -e "SYNTAX: $SCRIPTNAME OPTION [OPT_ARGS] [-- [BIN_ARGS]]*
\nwhere OPTION:
\n  -h|--help  : print this help information
  -d|--diff  : output diff to stdout
  -logTYPE [N] [ID]  : print log entries
\n    TYPE
      ''  :  simple log format
      1   :  single line log format
      x   :  extended log format
    [N]  : limit the number of results
    [ID]  : return results back starting from an id or partial
            description string. implies N=1 unless N specified\n
  -sha <ID> [N] [LOGTYPE]  : return commit sha / description for an id
                             or partial description string. use N to
                             limit the search range to the last N
                             commits. use LOGTYPE to switch output
                             format type as per the options above
  -st|--status      : show column format status with untracked local
                      path files only
  -sta|--status-all : show column format status
  -anws|--add-no-whitespace  : stage non-whitespace-only changes
  -fp|--format-patch [OPTION] [ID]
    : format one or more commits as patch file(s) up to a specified
      id or partial description string (default: HEAD)
\n    where OPTION:
      [-l|--limit] N  : format N patches up to the target ID
      -r|--root  : format all patches in current branch
\n  -rb|--rebase <ID> [N]  : interactively rebase back from id or partial
                           description string. use N to limit the search
                           range to the last N commits
  -rbs|--rebase-stash <ID> [N]  : same as 'rebase', but uses git's
                                 'autostash' feature
  -b|--blame <PATH> <SEARCH>  : filter blame output for PATH on SEARCH
                                and offer 'show' / 'rebase' options per
                                match
  -cl|-clone <REPO>  : clone repo
  -co|--checkout     : checkout files / branches
  -c|--commit                 : commit
  -ca|--commit-amend          : commit, amending previous
  -can|--commit-amend-noedit  : commit, amending previous without
                                editing message
  -ac|--add-commit                : add updated and commit
  -aca|--add-commit-amend         : add updated and commit, amending
                                    previous commit message
  -acan|-add-commit-amend-noedit  : add updated and commit, amending
                                    previous without editing message
  -ff|--fast-forward  : identify current 'branch' and fast-forward to
                        HEAD of 'linked'
  -rd|--rescue-dangling  : dump any orphaned commits still accessable
                           to a 'commits' directory
  -dc|--date-check TYPE [OPTIONS] TARGET
\n    where TYPE :
      order  : highlight non-chronological TARGET commit(s)
      timezone  : highlight TARGET commit(s) with invalid timezone
                  given locale's daylight saving rules
\n    and OPTIONS can be:
      -dt|--date-type TYPE  : check on date type TYPE, supporting
                              'authored' (default) or 'committed'
      -i|--issues  : only output highlighted commits
\n  -ds|--date-sort [OPTION]  : rebase all commits in current branch
                              onto an empty master branch of a new
                              repository in a date sorted order
\n    where OPTION:
      -r|--resume ID TARGET  : continue to create TARGET repo with ID
                               the next patch to push. ID is either a
                               number corresponding to the original
                               failed patch, or the (partial) id of
                               the patch itself
\n  -smr|--submodule-remove <NAME> [PATH]  : remove a submodule named
                                           NAME at PATH (default: NAME)
  -fb|--find-binary  : find all binary files in the current HEAD
\n*note: optional binary args are supported for commands:
       log, rebase, formatpatch, add-no-whitespace, commit
"
}

fn_commit() {
  declare message; message=""
  while [ -n "$1" ]; do
    arg="$(echo "$1" | sed 's/^[ ]*-*//')"
    [ -z "$arg" ] && shift && break
    [ ${#arg} -lt ${#1} ] && \
      echo "[error] unsupported arg '$1'" 1>&2 && return 1
    message="$message $1"
    shift
  done
  git commit -m "$message" "$@"
}

fn_search_commit_by_name() {
  [ $# -lt 1 ] && echo "[error] search arg missing" 1>&2 && return 1
  declare -a bin_args
  declare -a cmd_args; cmd_args=("--oneline")
  declare commits_
  declare -a commits
  declare search
  limit=1
  while [ -n "$1" ]; do
    case "$1" in
      "nolimit") limit=-1 ;;
      "colours") bin_args=("-c" "color.ui=always") ;;
      *)
        if [ "x$(echo "$1" | sed -n '/^[0-9-]\+$/p')" != "x" ]; then
          cmd_args=("${cmd_args[@]}" "-n" $1)
        elif [ -z $search ]; then
          search="$1"
        else
          echo "[info] unknown arg '$1', ignoring" 1>&2
        fi
        ;;
    esac
    shift
  done
  commits_="$(git "${bin_args[@]}" log "${cmd_args[@]}" | grep "$search" | sed 's/\\n/\\\\n/g')"
  IFS=$'\n'; commits=($(echo -e "$commits_")); IFS="$IFSORG";
  [ ${#commits[@]} -eq 0 ] &&
    echo "[info] no commits found matching search '$search'" 1>&2 && return 1
  [[ ${#commits[@]} -gt 1 && limit -eq 1 ]] &&
    echo "[info] multiple commits matching search '$search'" \
         "found. try a more specific search string, else use" \
         "the [N] argument to limit the commit range" 1>&2 && return 1
  [ $limit -eq -1 ] && limit=${#commits[@]}
  echo -e "$commits_" | tail -n $limit
  return 0
}

fn_search_commit() {
  [ $# -lt 1 ] && echo "[error] id arg missing" 1>&2 && return 1
  declare res
  declare search; search="$1" && shift
  declare commit
  commit="$(git rev-list --max-count=1 "$search" 2>/dev/null)"
  if [ $? -ne 0 ]; then
    commit="$(fn_search_commit_by_name "$search" "$@")"
    res=$?; [ $res -ne 0 ] && return $res
  fi
  echo "$commit"
  return 0
}

fn_log() {
  declare command; command="$1" && shift
  declare search; search=""
  declare path; path=""
  declare count
  declare -a bin_args; [ $term -eq 1 ] && bin_args=("-c" "color.ui=always")
  declare -a cmd_args; cmd_args=("--decorate")
  declare commits_
  declare -a commits
  while [ -n "$1" ]; do
    [ "x$(echo "$1" | sed -n '/^[0-9]\+$/p')" != "x" ] && count=$1 && shift && continue
    [ "x$(echo "$1" | sed -n '/^[^-]\+/p')" != "x" ] && search=$1 && shift && continue
    if [ "x$1" = "x--" ]; then
      shift
      while [ -n "$1" ]; do
        [ -n "$(git rev-list -n1 HEAD -- "$1" 2>/dev/null)" ] && \
          path="$1" || \
          cmd_args[${#cmd_args[@]}]="$1"
        shift
      done
      break
    fi
    cmd_args[${#cmd_args[@]}]="$1"
    shift
  done
  if [ -n "$search" ]; then
    commits_="$(fn_search_commit "$search" "${count:-nolimit}")"
    res=$?; [ $res -ne 0 ] && exit $res
    IFS=$'\n'; commits=($(echo "$commits_")); IFS="$IFSORG"
  elif [ -n "$path" ]; then
    commits=("$path")
  else
    commits=("HEAD")
  fi
  [ ${#commits[@]} -gt 1 ] && count=1
  [ -n "$count" ] && cmd_args=("-n" $count "${cmd_args[@]}")
  commit_last="$(echo "${commits[$((${#commits[@]}-1))]}" | cut -d' ' -f1)"
  for commit in "${commits[@]}"; do
    commit="$(echo "$commit" | cut -d' ' -f1)"
    if [ "x$command" = "xlog" ]; then
      git "${bin_args[@]}" log --format=format:"%at | %ct | version: $(printf ${clr["bwn"]})%H$(printf ${clr["off"]}) $(printf ${clr["ylw"]})%d$(printf ${clr["off"]})%n %s (%an)" "${cmd_args[@]}" $commit | awk '{if ( $0 ~ /[0-9]{10} \| [0-9]{10} | version:/ ) { $1=strftime("%Y%b%d %H:%M:%S %z",$1); $3=strftime("%Y%b%d %H:%M:%S %z",$3); }; print $0;}'
    else
      format="$([ "x$command" = "xlog1" ] && echo "oneline" || echo "fuller")"
      git "${bin_args[@]}" log --format="$format" "${cmd_args[@]}" $commit | cat
      [[ "x$command" == xlogx && "$commit" != "$commit_last" ]] && echo
    fi
  done
}

fn_rebase() {
  # process args
  [ $# -lt 1 ] && help && echo "[error] not enough args" && return 1
  declare root; root=0
  declare -a cmd_args; cmd_args[${#cmd_args[@]}]="-i"
  declare -a args
  while [ -n "$1" ]; do
    if [ "x$1" = "x--" ]; then
      while [ -n "$1" ]; do
        [ "x$1" = "x--" ] && shift && continue
        [ "x$1" = "x--root" ] && root=1
        cmd_args[${#cmd_args[@]}]="$1"
        shift
      done
      break
    fi
    args[${#args[@]}]="$1"
    shift
  done
  if [ $root -eq 0 ]; then
    commit=$(fn_search_commit "${args[@]}")
    res=$?; [ $res -ne 0 ] && return $res
    sha="$(echo $commit | sed -n 's/\([^ ]*\).*/\1/p')"
    # ensure parent exists, else assume root
    git rev-parse --verify "$sha^1"
    if [ $? -eq 0 ]; then
      cmd_args[${#cmd_args[@]}]="$sha~1"
    else
      root=1
      cmd_args[${#cmd_args[@]}]="--root"
    fi
  fi
  echo "[info] rebasing interactively from $([ $root -eq 1 ] && echo "root" || echo "commit '$commit~1'")"
  git rebase "${cmd_args[@]}"
}

fn_formatpatch() {
  declare id
  declare n
  declare root; root=0
  declare -a cmd_args
  while [ -n "$1" ]; do
    if [ "x$1" = "x--" ]; then
      # cmd args
      shift
      cmd_args=("$@")
      shift "$#"
      break
    else
      arg="$(echo "$1" | sed 's/^[ ]*-*//')"
      if [ -n "$(echo "$arg" | sed -n '/^[0-9]\+$/p')" ]; then
        n="$arg"
      elif [[ "x$arg" == "l" || "x$arg" == "xlimit" ]]; then
        n="$arg"
      elif [[ "x$arg" == "r" || "x$arg" == "xroot" ]]; then
        root=1
        id="HEAD"
      elif [ -z "$id" ]; then
        id="$arg"
      else
        echo "[error] unrecognised arg '$1'" && return 1
      fi
    fi
    shift
  done
  n=${n:-1}
  [ $root -eq 1 ] && n=$(($(git log --format="format:%h" | wc -l) + 1))
  id="${id:-"HEAD"}"
  commit=$(fn_search_commit "$id")
  res=$?; [ $res -ne 0 ] && exit $res
  sha="$(echo $commit | sed -n 's/\([^ ]*\).*/\1/p')"
  echo "[info] formatting patch for rebasing from commit '$commit'"
  git format-patch -k -$n $sha "${cmd_args[@]}"
}

fn_date_check() {
  declare target
  declare prev_commit
  declare prev_commit_date
  declare option
  declare -a args

  declare date_type
  declare issues_only; issues_only=0

  # process options
  while [ -n "$1" ]; do
    option="$1"
    case "$option" in
      "-dt"|"--date-type") shift; date_type="$1" && shift ;;
      "-i"|"--issues") shift; issues_only=1 ;;
      *) args[${#args[@]}]="$1"; shift ;;
    esac
  done

  [ ${#args[@]} -lt 1 ] && echo "[error] missing check type argument" && exit 1
  type="$(echo "${args[0]}" | sed -n '/\(order\|timezone\)/p')"
  [ -z "$type" ] && echo "[error] invalid check type '$1'" && exit 1
  args=("${args[@]:1}")
  [ ${#args[@]} -gt 0 ] && target="${args[0]}"; args=("${args[@]:1}")
  [ ${#args[@]} -gt 0 ] && _help && echo "[error] unrecognised arg(s): '${args[@]}'" && exit 1

  # default options
  target="${target:-HEAD}"
  date_type="${date_type:-authored}"

  # verify options
  [[ "x$date_type" != "xauthored" && "x$date_type" != "xcommitted" ]] && \
    _help && echo "[error] invalid type '$date_type' set" && exit 1
  declare -a commits
  IFS=$'\n'; commits=($(git rev-list --reverse "$target")); IFS="$IFSORG"
  [ ${#commits[@]} -lt 1 ] && \
    _help && echo "[error] invalid target '$target'" && exit 1

  prev_commit="$(git rev-list --max-count=1 "${commits[0]}~1" 2>/dev/null)"
  if [ -n "$prev_commit" ]; then
    prev_commit_date="$(git log -n1 --format=format:"%$([ "x$type" = "xauthored" ] && echo "a" || echo "c")t" "$prev_commit")"
  fi

  [ $DEBUG -ge 1 ] && echo "[debug] previous commit date: '$prev_commit_date'" 1>&2
  git log --reverse --format=format:"authored: %ad | committed: %cd | version: ${clr["bwn"]}%H${clr["off"]}%n %s (%an)" "${cmdargs[@]}" "$target" | awk \
    -v type="$type" \
    -v date_type=$date_type \
    -v issues_only=$issues_only \
    -v pcd="$prev_commit_date" \
'
function dateToEpoch(dt    , dt_, parts) {
  # DATESPEC (git): Sun Sep 8 11:32:38 2013 +0100
  # DATESPEC (awk): 2015 02 26 16 02 32 -1  : auto dst
  split(dt, parts, " ");
  if (length(parts) != 6)
    return ""
  time_ = parts[4];
  gsub(/:/, " ", time_);
  dt_ = parts[5]" "month_idx[parts[2]]" "parts[3]" "time_" -1";
  #print("dt_: "dt_);
  return mktime(dt_);
}

func dateLongToShort(dt,    parts) {
  split(dt, parts, " ")
  day = parts[3];
  if (length(day) == 1)
    day = "0"day;
  return parts[5]parts[2]day" "parts[4]" "parts[6];
}

func check_order(dt1, dt2) {
  if (dt1 >= dt2)
    return 1;
  else
    return 0;
}

func check_timezone(dt,    parts) {
  split(dt, parts, " ")
  dt = parts[3]"-"parts[2]"-"parts[5]" "parts[4];
  z_orig=parts[6]
  cmd = "date -d\""dt"\" \"+%z\""
  cmd | getline z_actual
  close(cmd)
  #print("checking timezone dt: "dt", z-orig: "z_orig" vs z-actual: "z_actual)
  if (z_orig != z_actual)
    return 1;
  else
    return 0;
}

BEGIN {
  s="Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
  split(s, months, "|")
  for (idx in months) month_idx[months[idx]] = idx
  #for (idx in month_idx) print("["idx"] : "month_idx[idx]);

  state = 0;
  last = dateToEpoch(pcd);
}
{
  if ( $0 ~ /^authored: [A-Z][a-z]{2}.*/ ) {
    split($0, sections, "|");

    #for (idx in sections) print("["idx"]: "sections[idx]);

    section = date_type == "authored" ? 1 : 2
    test = sections[section];
    gsub(/^[^:]*: /, "", test);
    gsub(/ *$/, "", test);
    dt = test;
    dt_ = dateLongToShort(dt);
    dt__ = dateToEpoch(dt);
    test = sections[section];

    #print("test: "test);

    expr = dt;
    sub(/+/, "\\+", expr);

    #print("testing: authored, dt: "dt", dt_: "dt_", dt__: "dt__);

    if (type == "order") {
      if (last != "")
        issue = check_order(last, dt__);
      last = dt__;
    } else if (type == "timezone")
      issue = check_timezone(dt);

    if (issue == 1) {
      state = 2;
      dt_="'"${clr["red"]}"'"dt_"'"${clr["off"]}"'";
    } else
      dt_="'"${clr["red"]}${clr["off"]}"'"dt_;

    sub(expr, dt_, sections[section]);

    #print("final section: "sections[section]);

    # modify other date
    section = section == 1 ? 2 : 1;
    test = sections[section];
    gsub(/^[^:]*: /, "", test);
    gsub(/ *$/, "", test);
    dt = test;
    dt_ = dateLongToShort(dt);
    test = sections[section];
    expr = dt;
    sub(/+/, "\\+", expr);
    sub(expr, dt_, sections[section]);

    # mod line
    $0 = "";
    for (idx in sections) $0 = $0"|"sections[idx];
    $0 = substr($0, 2);
  }

  if (issues_only == 1) {
    if (state == 0)
      next;
    state--;
  }
  print $0;
}'
}

fn_date_sort() {

  declare target
  declare -a patches
  declare l_patches
  declare -a ordered
  declare s
  declare commit
  declare -a parts
  declare l_ordered
  declare l
  declare id
  declare idx_start; idx_start=0

  declare resume; resume=0
  declare resume_id
  declare resume_target

  declare option
  # process options
  while [ -n "$1" ]; do
    option="$1"
    case "$option" in
      "-r"|"--resume")
        shift
        resume=1
        [ $# -gt 0 ] && resume_id="$1" && shift
        [ $# -gt 0 ] && resume_target="$1" && shift
        ;;
      *)
        help && echo "[error] unsupported option '$option'" 1>&2 && return 1
        ;;
    esac
  done

  # validate options
  if [ $resume -eq 1 ]; then
    [ -z "$resume_id" ] && help && echo "[error] missing ID arg" 1>&2 && return 1
    [ -z "$resume_target" ] && help && echo "[error] missing TARGET arg" 1>&2 && return 1
    [ ! -d "$resume_target" ] && help && echo "[error] invalid target directory '$resume_target'" 1>&2 && return 1
  fi

  echo "[info] rebuilding repository with commits ordered by date"

  IFS=$'\n'; ordered=($(git log --format="format:%at|%H|%s" | sort)); IFS="$IFSORG"
  l_ordered=${#ordered[@]}

  if [ -n "$resume_target" ]; then
    target="$resume_target"
    cd "$target"
    # set start idx
    s_="$(echo "$resume_id" | sed -n 's/^ *\([0-9]\+\) *$/\1/p')"
    if [[ -n "$s_" && $s_ -le $l_ordered ]]; then
      idx_start=$((s_ - 1))
      resume_id="$(echo "${ordered[$idx_start]}" | sed 's/^[^|]\+|\([^|]\+\).*/\1/')"
    else
      declare -a matches
      IFS=$'\n'; matches=($(find "$resume_target" -name "*$resume_id*")); IFS="$IFSORG"
      [ ${#matches[@]} -eq 0 ] && echo "[error] cannot find next patch at target '$target' based on (partial) id match '$resume_id'" 1>&2 && return 1
      [ ${#matches[@]} -ge 0 ] && echo "[error] partial id '$resume_id' matched multiple patches at target '$target', uniqueness is required" 1>&2 && return 1
      s_="$(echo "${matches[0]}" | sed 's/\(.\*\/\)\?\(.*\)\..*$/\2/p')"
      resume_id="$s_"
      while [ "x${ordered[$idx_start]}" != "x$resume_id" ]; do
        idx_start=$((idx_start + 1))
      done
    fi
    echo "[info] resuming from commit '$((idx_start + 1))|$resume_id'"
  else
    target="$(fn_temp_dir "$SCRIPTNAME" ".")"
    fn_formatpatch "root" -- -o "$target" >/dev/null
    cd "$target"
    git init 2>/dev/null 1>&2
    IFS=$'\n'; patches=($(find "." -type f -name "*patch")); IFS="$IFSORG"
    l_patches=${#patches[@]}
    for f in "${patches[@]}"; do
      commit="$(sed -n 's/^From \([0-9a-f]\{40\}\) .*$/\1/p' "$f")"
      mv "$f" "./$commit.diff"
    done
  fi

  echo "[info] applying $((l_ordered - (idx_start + 1))) commit$([ $((l_ordered - (idx_start + 1))) -ne 1 ] && echo "s")"

  l=$idx_start
  while [ $l -lt $l_ordered ]; do
    IFS="|"; parts=($(echo "${ordered[$l]}")); IFS="$IFSORG"
    id="${parts[1]}"
    l=$((l + 1))
    echo "applying patch: [$l] ${clr["hl"]}${id:0:7}${clr["off"]} | '${parts[2]}'"
    git am --keep-non-patch "$id.diff" >/dev/null || return 1
  done
}

fn_submodule_remove() {
  [ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
  submodule="$1" && shift
  submodule_path="$submodule"
  [ $# -gt 0 ] && submodule_path="$1" && shift
  echo "[info] removing git submodule internals"
  git config -f .git/config --remove-section submodule."$submodule"
  git config -f .gitmodules --remove-section submodule."$submodule"

  echo "[info] committing changes.."
  sleep 0.5
  git add .gitmodules
  git commit -m "[mod] removed submodule '$submodule'"

  echo "[info] purging internal cache.."
  git rm --cached "$submodule_path"

  if [ -d $submodule_path ]; then
    echo "[info] removing submodule path: '$submodule_path'"
    rm -rf .git/modules/"$submodule"
    rm -rf "$submodule_path"
    # remove any empty parent paths
    path="$submodule_path"
    while [ ${#path} -gt 1 ] ; do
      path=${path%/*}
      rmdir "$path" 2>/dev/null || break
    done
  else
    echo "[info] submodule path: '$submodule_path' missing / already removed"
  fi
}

fn_sha() {
  [ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
  declare -a cmd_args
  cmd_args=("nolimit")
  log=""
  while [ -n "$1" ]; do
    case "$1" in
      "log"|"log1"|"logx") log="$1" ;;
      *) cmd_args[${#cmd_args[@]}]="$1" ;;
    esac
    shift
  done
  [ -z $log ] && cmd_args[${#cmd_args[@]}]="colours"
  commits=$(fn_search_commit "${cmd_args[@]}")
  res=$?; [ $res -ne 0 ] && exit $res
  if [ -z $log ]; then
    echo -e "$commits"
  else
    IFS=$'\n'; arr_commits=($(echo -e "$commits")); IFS="$IFSORG"
    for c in "${arr_commits[@]}"; do
      fn_log $log 1 "$(echo "$c" | cut -d' ' -f1)"
      [ "x$log" = "xlogx" ] && echo
    done
  fi
}

fn_status() {
  gitstatus=(git -c color.ui=always status)
  gitcolumn=(git column --mode=column --indent=$'\t')
  m="Untracked files:"
  # pre
  "${gitstatus[@]}" | sed -n '1,/^'"$m"'/{/^'"$m"'/{s/\(.*\):/\1 [local dir only]:/;N;N;p;b};p;}'
  # filtered
  "${gitstatus[@]}" | sed -n '/^'"$m"'/,/^*$/{/'"$m"'/{N;N;d;};/^$/{N;N;d;};/\/[^[:cntrl:]]/d;s/^[ \t]*//g;p;}' | "${gitcolumn[@]}"
  # post
  "${gitstatus[@]}" | sed -n '/^'"$m"'/,${/^'"$m"'/{N;N;d;};/^$/,${p;};}'
}

fn_add_no_whitespace() {
  echo "[info] git, staging non-whitespace-only changes"
  git diff --ignore-all-space --no-color --unified=0 "$@" | git apply --cached --ignore-whitespace --unidiff-zero
}

fn_fast_foward() {
  num=$1 && shift;
  target="$(git rev-parse --abbrev-ref HEAD)"
  [ "x$target" = "xHEAD" ] && target="$(git status | sed -n "s/.* branch '\([^']\{1,\}\)'.*/\1/p" | head -n1)"
  sha_current="$(git log --oneline -n1 | cut -d' ' -f1)"
  sha_target="$(git log --oneline $target | grep $sha_current -B $num | head -n1 | cut -d' ' -f1)"
  echo -n "[info] fast-forwarding $num commits, '$sha_current' -> '$sha_target' on branch '$target', ok?"
  fn_decision >/dev/null && git checkout $sha_target
}

fn_rescue_dangling() {
  IFS=$'\n'; commits=($(git fsck --no-reflog | awk '/dangling commit/ {print $3}')); IFS="$IFSORG"
  if [ ${#commits[@]} -eq 0 ]; then
    echo "[info] no dangling commits found in repo"
  else
    echo -n "[info] rescue ${#commits[@]} dangling commit$([ ${#commits[@]} -ne 1 ] && echo "s") found in repo? [y/n]: "
    fn_decision >/dev/null &&\
      mkdir commits &&\
      for c in "${commits[@]}"; do git log -n1 -p $c > commits/$c.diff; done
  fi
}

fn_blame() {
  [ $# -lt 2 ] && help && echo "[error] not enough args" && exit 1
  file="$1" && shift
  res="$(git log "$file" >/dev/null 2>&1)"
  [ $? -ne 0 ] && echo "[error] invalid path '$file'" && exit 1
  search="$(fn_escape "ere" "$1")"
  IFS=$'\n'; matches=($(git blame -lt "$file" | grep -E "$search")); IFS="$IFSORG"
  echo "[info] ${#matches[@]} hit$([ ${#matches[@]} -ne 1 ] && echo "s") for search string '$search' on file '$file'"
  [ ${#matches[@]} -eq 0 ] && exit
  for s in "${matches[@]}"; do
    parts=($(echo "$s"))
    id="$(echo "${parts[0]}" | sed 's/^\^//')"
    x="$(echo "${s:$((${#parts[0]}+1))}" | sed 's/^(^\?\([^)]*\)) /\1|/')"
    xa=(${x%%|*})
    dt1="${xa[$((${#xa}-2))]}"
    dt2="${xa[$((${#xa}-1))]}"
    line="${xa[$((${#xa}-0))]}"
    auth="$(echo "${xa[@]}" | sed 's/ '$dt1'.*$//')"
    data="${x#*|}"
    echo -e "[info] file: $file | ln#: $line | auth: ${clr["red"]}${auth}${clr["off"]} | date: $(date -d "@$dt1" "+%d %b %Y %H:%M:%S") $dt2"
    echo -e "\n$data\n"
    res="$(fn_decision "[user] (s)how, (r)ebase from, or (i)gnore commit '$id'?" "srix")"
    [ "x$res" = "xs" ] && git show "$id"
    [ "x$res" = "xr" ] && { fn_rebase "$id" -- --autostash; exit; }
    [ "x$res" = "xi" ] && continue
    [ "x$res" = "xx" ] && exit
  done
}

fn_find_binary() {
  git log --numstat "$@" | sed -n 's/^-[\t -]*//p'| sort -u
}

fn_process() {
  option="help"
  [ $# -gt 0 ] && option="$(echo "$1" | sed 's/[ ]*-*//')" && shift
  case "$option" in
    "h"|"help") help ;;
    "d"|"diff") git diff "$@" ;;
    "c"|"commit") fn_commit "$@" ;;
    "log"|"logx"|"log1") [ $term -eq 1 ] && fn_log "$option" "$@" | less -R || fn_log "$option" "$@" ;;
    "sha") fn_sha "$@" ;;
    "st"|"status") fn_status "$@" ;;
    "sta"|"status-all") git status --col ;;
    "anws"|"add-no-whitespace") fn_add_no_whitespace "$@" ;;
    "fp"|"formatpatch"|"format-patch") fn_formatpatch "$@" ;;
    "rb"|"rebase") fn_rebase "$@" ;;
    "rbs"|"rebase-stash") fn_rebase "$@" -- --autostash ;;
    "co"|"checkout") git checkout "$@" ;;
    "cl"|"clone") git clone "$@" ;;
    "ca"|"commit-amend") git commit --amend "$@" ;;
    "can"|"commit-amend-noedit") git commit --amend --no-edit "$@" ;;
    "ac"|"add-commit") git add -u . && git commit ;;
    "aca"|"add-commit-amend") git add -u . && git commit --amend ;;
    "acan"|"add-commit-amend-noedit") git add -u . && git commit --amend --no-edit "$@" ;;
    "ff"|"fast-forward") fn_fast_foward "$@" ;;
    "rd"|"rescue-dangling") fn_rescue_dangling "$@" ;;
    "b"|"blame") fn_blame "$@" ;;
    "dc"|"date-check") fn_date_check "$@" ;;
    "ds"|"date-sort") fn_date_sort "$@" ;;
    "smr"|"submodule-remove") fn_submodule_remove "$@" ;;
    "fb"|"find-binary") fn_find_binary "$@" ;;
    *) git "$option" "$@" ;;
  esac
}

fn_sourced() {
  # support for being 'sourced' limited to bash and zsh
  [ $DEBUG -gt 0 ] && echo "[info] \$0: '$0', ZSH_VERSION: '$ZSH_VERSION', ZSH_EVAL_CONTEXT: '$ZSH_EVAL_CONTEXT', BASH_VERSION: '$BASH_VERSION', BASH_SOURCE[0]: '${BASH_SOURCE[0]}'" 1>&2
  [ -n "$BASH_VERSION" ] && ([[ "${0##*/}" == "${BASH_SOURCE##*/}" ]] &&  echo 0 || echo 1) && return
  [ -n "$ZSH_VERSION" ] && ([[ "$ZSH_EVAL_CONTEXT" =~ ":file" ]] && echo 1 || echo 0) && return
  echo 0
}

[ $(fn_sourced) -eq 0 ] && fn_process "$@"
