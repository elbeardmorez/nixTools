#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG=$IFS
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}
trap fn_exit EXIT

declare -a temp_data

declare -A changelog_profile_rx_file
changelog_profile_file["default"]='CHANGELOG.md'
changelog_profile_file["update"]='CHANGELOG.md'
declare -A changelog_profile_rx_id
changelog_profile_rx_id["default"]='version \([^ ]*\)'
changelog_profile_rx_id["update"]='version: \([^ ]*\)'
declare -A changelog_profile_anchor_entry
changelog_profile_anchor_entry["default"]=1
changelog_profile_anchor_entry["update"]=3

declare -A commits_info
RX_COMMITS_AUTHOR="${RX_COMMITS_AUTHOR:-""}"
RX_COMMITS_DESCRIPTION_DEFAULT='s/^[ ]*\(.\{20\}[^.]*\).*$/\1/'
RX_COMMITS_DESCRIPTION="${RX_COMMITS_DESCRIPTION:-"$RX_COMMITS_DESCRIPTION_DEFAULT"}"

help() {
  declare -A sections
  sections["refactor"]="
  -r|--refactor  : perform code refactoring
\n    SYNTAX: $SCRIPTNAME refactor [ARGS] TARGETS
\n    ARGS:
      -f|--filter FILTER  : regexp filter to limit files to work on
                            (default: '.*')
      -d|--depth MAXDEPTH  : limit files to within MAXDEPTH target
                             hierarchy level (default: 1)
      -m|--modify  : persist transforms
      -t|--transforms TRANSFORMS  : override default refactor
                                    transforms set. TRANSFORMS is a
                                    comma delimited list of supported
                                    transforms. the 'all' transform
                                    enables all implemented transforms
                                    (default: tabs,whitespace)
\n          TRANFORMS:
            tabs  : replace tab characters with 2 spaces
            whitespace  : remove trailing whitespace
            braces  : inline leading control structure braces
\n      -xi|--external-indent [PROFILE]  : use external gnu indent
                                         binary with PROFILE
                                         (default: standard*)
                                         (support: c)
\n      *note: see README.md for PROFILE types
\n    TARGETS  : target file(s) / dir(s) to work on"
  sections["debug"]="
  -d|--debug  : call supported debugger
\n    SYNTAX: $SCRIPTNAME debug [-l LANGUAGE] [-d DEBUGGER]
                                [ARGS] [-- BIN_ARGS]
\n    -l|--language LANGUAGE  : specify target language (default: c)
    -d|--debugger  : override language specific default debugger
\n    ARGS:
      gdb:  NAME, [PID]
      node inspect:  SRC, [PORT]
\n      note: the above args are overriden by default by environment
            variables of the same name, and where not, are consumed
            in a position dependent manner
\n    support: c/c++|gdb, javascript|node inspect"
  sections["changelog"]="
  -cl|--changelog
\n    SYNTAX: $SCRIPTNAME changelog [ARGS] [TARGET]
\n    ARGS:
      -as|--anchor-start NUMBER  : start processing entries at line
                                   NUMBER, allowing for headers etc.
      -p|--profile NAME  : use profile temple NAME
\n        NAME:
          default:  %date version %id\\\n - %description (%author)
          update:  [1] \\\n##### %date\\\nrelease: %tag version: $id
                   [>=1]- %description ([%author](%email))
\n      -f|--file FILE  : overwrite changelog file name
                        (default: '${changelog_profile_file["default"]}')
      -rxid|--rx-id REGEXP  : override (sed) regular expression used
                              to extract ids and thus delimit entries
                              (default: '${changelog_profile_rx_id["default"]}')
      -ae|--anchor-entry NUMBER  : override each entry's anchor line
                                   (line containing %id)
                                   (default: '${changelog_profile_anchor_entry["default"]}')
\n    TARGET:  location of repository to query for changes"
  sections["commits"]="
  -c|--commits  : process source diffs into a target repo
\n    SYNTAX: $SCRIPTNAME commits [OPTIONS] [SOURCE] TARGET
\n    with OPTIONS in:
      -st|--source-type [=TYPE]  : set source type
\n        with TYPE:
          vcs  : a version control repository
          dir  : a directory of patch files
          patch  : a single patch file
          auto  : automatically determined based on the above order
                  of precedence (default)
\n      -l|--limit [=LIMIT]  : limit number of patches to process to
                             LIMIT (default: 1)
      -f|--filter [=]FILTER  : only use commits matching the (regex)
                               expression FILTER. repeated filter args
                               are supported
      -rm|--repo-map [=CATEGORY]  : push diffs to sub-directory based
                                    upon the comma delimited CATEGORY
                                    list, with each item corresponding
                                    to a tier in the hierarchy
                                    (default: target directory name)
      -mrm|--multi-repo-map [=REPOS]  :
        map diffs to repositories selected from the comma delimited
        REPOS list
        (default: fix,mod,hack)
      -vcs|--version-control-system [=][SOURCE|]TARGET  :
        pipe-delimited override of default version control system
        types. support for source: git, subversion | target: git
        (default: git)
      -d|--dump  : dump patch set only
      -o|order [=]TYPE  : process patchset in a specific order, which
                          in turn governs target output / commit order
                          (default: 'default')
\n        with TYPE:
          date  : patchset is processed in date order
          default  : patchset is processed in source order
\n      -im|--interactive-match  : interactively match when target diff
                                 name clashes are unresolvable
                                 (default: assumes 'new')
      -rn|--readme-name [=]NAME  : override default readme file name
                                   (default: README.md)
      -rs|--readme-status [=STATUS]  : append a commit status string
                                       to the readme entry
                                       (default: pending)
      -nr|--no-readme  : don't update target readme(s)
      -ac|--auto-commit [=MODE]  : attempt to commit to target repo(s)
                                   non-interactively
\n        with MODE:
          auto  : commit set unconditionally (default)
          verify  : require user verification prior to execution
\n    SOURCE  : location of repository to extract/use patch set from
              (default: '.')
\n    TARGET  : location of repository / directory to push diffs to"
  sections["port"]="
  -p|--port  : apply a set of tranforms to a source file
\n    SYNTAX: $SCRIPTNAME port [OPTIONS] TARGET
\n    with OPTIONS in:
      -x|--transforms FILE  : override location of file containing
                              transforms
                              (default: ~/.nixTools/$SCRIPTNAME*)
      -xs|--transforms-source TYPE  : apply source transforms of TYPE
                                      (default: target file suffix)
      -xt|--transforms-target TYPE  : apply target transforms of TYPE
                                      (default: target file suffix)
      -xd|--transforms-debug LINE  : trace transforms at LINE(S)
                                     in a comma-delimited list
      -l|--lines RANGE  : limit replacements to lines specified by a
                          comma-delimited list of delimited RANGE(S)
      -d|--diffs  : show diffs pre-transform
      -o|--overwrite  : persist changes to target
      -v|--verify  : interactive application of transforms
      -ie|--ignore-errors  : continue processing on error
\n    * transform format:
\n    FROM|TO [FROM2|TO2 ..]
    TRANSFORM
\n    where:
\n      FROM  : source language type
      TO  : target language type
      TRANSFORM  : valid sed expression"

  declare section; section="${1:-all}"
  declare -a sections_=("refactor" "debug" "changelog" "commits" "port")
  declare s
  if [ "x$section" = "xall" ]; then
    echo -e "SYNTAX: $SCRIPTNAME [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]
\nwith OPTION:
  -h|--help [=OPTION]  : this information"
    for s in "${sections_[@]}"; do echo -e "${sections["$s"]}"; done
  else
    s="${sections["$section"]}"
    [ -z "$s" ] && \
      { echo "[error] invalid help option '$section' [supports: $(fn_str_join "|" "${sections_[@]}")]" 1>&2 && return 1; }
    echo -e "${clr["hl"]}$(echo -e "$s" | sed -n '1,/^[ ]*SYNTAX/{1{N;s/^[^:]*:[ ]*//;};/^[ ]*SYNTAX/{x;s/\n[ ]*/\n/g;p;};H;}')${clr["off"]}\n"
    echo -e "$s\n" | sed -n '1,/^[ ]*SYNTAX/{/^[ ]*SYNTAX/{s/^[ ]*//;p;};b;};s/^  //;p'
  fi
}

fn_exit() {
  code=$?
  [ $# -gt 0 ] && code=$1 && shift
  fn_cleanup
  exit $code
}

fn_cleanup() {
  for s in "${temp_data[@]}"; do
    [[ -e "$s" && "x$s" != "x/" ]] && rm -rf "$s" >/dev/null 2>&1
  done
}

fn_repo_type() {
  declare vcs=""
  declare target="$1"
  [ ! -d "$target" ] && \
    { echo "[error] invalid vcs root '$target'" 1>&2 && return 1; }
  if [ -d "$target/.git" ]; then vcs="git"
  elif [ -d "$target/.svn" ]; then vcs="subversion"
  elif [ -d "$target/.bzr" ]; then vcs="bazaar"
  elif [ -d "$target/.hg" ]; then vcs="mercurial"
  elif [ -d "$target/.cvs" ]; then vcs="cvs"
  fi
  echo "$vcs"
  [ -n "$vcs" ] && return 0 || return 1
}

fn_patch_name() {
  declare description="$1" && shift
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

fn_repo_search() {
  declare target; target="$1" && shift
  declare limit; limit=$1 && shift
  declare res
  declare -a commits; commits=()
  declare search
  declare commit
  declare processed
  declare parts
  declare id
  declare vcs
  declare s
  vcs="$(fn_repo_type "$target")" || \
    { echo "[error] unknown vcs type for source directory '$target'" 1>&2 && return 1; }
  cd "$target" 1>/dev/null
  case "$vcs" in
    "git")
      declare -a cmd_args
      cmd_args=("--format=format:%at|%H|%an <%ae>|%s")
      if [ $# -eq 0 ]; then
        [ $limit -gt 0 ] && cmd_args[${#cmd_args[@]}]="-n$limit"
        IFS=$'\n'; commits=($(git log "${cmd_args[@]}")); IFS="$IFSORG"
      else
        cmd_args[${#cmd_args[@]}]="-P"
        cmd_args[${#cmd_args[@]}]="--grep='$1'"
        res=""
        declare match
        declare -a matches
        IFS=$'\n'; matches=($(git log "${cmd_args[@]}")); IFS="$IFSORG"
        for commit in "${matches[@]}"; do
          match=1
          for search in "$@"; do
            [ -z "$(echo "$commit" | grep -P "$search")" ] && \
              { match=0 && break; }
          done
          if [ $match -eq 1 ]; then
            res="$res\n$commit"
            processed=$((processed + 1))
            [[ $limit -gt 0 && $processed -eq $limit ]] && break
          fi
        done
        [ ${#res} -gt 0 ] && \
          { IFS=$'\n'; commits=($(echo "${res:2}")); IFS="$IFSORG"; }
      fi
      res=""
      if [ ${#commits[@]} -gt 0 ]; then
        for commit in "${commits[@]}"; do
          IFS="|"; parts=($(echo "$commit")); IFS="$IFSORG"
          id="${parts[1]}"
          s="$commit|$(git log --format="format:%b" "$id" | sed 's/\n/\\\\n/g;s/\(\n\)*$//;')"
          res="$res\n$s"
        done
        res="${res:2}"
      fi
      echo -e "$res" | tac
      ;;

    "subversion")
      declare head_; head_=$(svn info | sed -n 's/Revision: //p')
      declare match
      declare -a matches
      declare -a cmd_args
      declare filter; filter=0
      cmd_args[${#cmd_args[@]}]="--xml"
      if [ $# -gt 0 ]; then
        filter=1
        cmd_args[${#cmd_args[@]}]="--search"
        cmd_args[${#cmd_args[@]}]="$1"
        shift
        while [ -n "$1" ]; do
          cmd_args[${#cmd_args[@]}]="--search-and"
          cmd_args[${#cmd_args[@]}]="$1"
          shift
        done
      fi
      declare batch; batch=$limit
      [ $batch -lt 1 ] && batch=100
      declare r1
      declare r2; r2=$head_
      processed=0
      while true; do
        cmd_args_=("${cmd_args[@]}")
        if [ $filter -eq 0 ]; then
          # buffer
          r1=$((r2 - batch + 1))
          [ $r1 -lt 1 ] && r1=1
          cmd_args_[${#cmd_args_[@]}]="-r$r1:$r2"
        fi
        IFS=$'\n'; matches=($(svn log "${cmd_args_[@]}" | sed -n '/<logentry/,/<\/logentry>/{/<\/logentry>/{x;s/\n/\\\\n/g;s/^.*revision="\([^"]*\).*<author>\([^<]*\).*<date>\([^<]\+\).*<msg>\(.*\)<\/msg.*$/\3\|r\1|\2|\4/;s/\(\\\\n\)*$//;p;b;};H;}')); IFS="$IFSORG"
        [ ${#matches[@]} -eq 0 ] && break
        for commit in "${matches[@]}"; do
          res="$res\n$(date -d "${commit%%|*}" "+%s")|${commit#*|}"
          processed=$((processed + 1))
          [[ $limit -gt 0 && $processed -eq $limit ]] && break
        done
        [ $filter -eq 1 ] && break  # one shot
        r2=$((r2 - batch))
        [[ $processed -eq $limit || $r2 -lt 1 ]] && break
      done
      echo -e "${res:2}" | tac
      ;;
    *)
      echo "[error] vcs type: '$vcs' not implemented" 1>&2 && return 1
      ;;
  esac
  cd - 1>/dev/null || return 1
}

fn_repo_pull() {
  declare target="$1" && shift
  declare id_out
  declare id
  declare vcs
  vcs="$(fn_repo_type "$target")" || return 1
  cd "$target" 1>/dev/null
  while [ -n "$1" ]; do
    id_out="$1" && shift
    id="${id_out%|*}"
    out="${id_out#*|}"
    fn_patch_format "$vcs" "$id" "$out" || return 1
  done
  cd - 1>/dev/null || return 1
}

fn_patch_format() {
  declare vcs; vcs="$1" && shift
  declare id; id="$1" && shift
  declare out; out="$1" && shift
  case "$vcs" in
    "git")
      git format-patch -k --stdout -1 "$id" > "$out"
      ;;

    "subversion")
      info="${commits_info["$id"]}"
      [ -z "$info" ] && \
        { echo "[error] missing cached commit info for id: '$id'" 1>&2 && return 1; }
      IFS="|"; parts=($(echo "$info")); IFS="$IFSORG"
      dt="$(date -d "@${parts[0]}" "+%a %d %b %Y %T %z")"
      id="${parts[1]}"
      author="$(echo "${parts[2]}" | sed "$RX_COMMITS_AUTHOR")"
      message="${parts[3]}"
      echo -e "Author: $author\nDate: $dt\nRevision: $id\nSubject: $message\n" > "$out"
      svn diff --git -c${id#r} >> "$out"
      ;;

    *)
      echo "[error] vcs source type: '$vcs' not implemented" 1>&2 && return 1
      ;;
  esac
}

fn_patch_transform() {
  declare vcs_source; vcs_source="$1" && shift
  declare vcs_target; vcs_target="$1" && shift
  declare target; target="$1" && shift

  if [[ "x$vcs_source" == "xsvn" && "x$vcs_target" == "xgit" ]]; then
    sed -i '/^Revision/{d;b;};s/^Author/From/'
  else
    echo "[error] unsupported vcs source / target pair '$vcs_source -> $vcs_target'" 1>&2 && return 1
  fi
}

fn_patch_info() {
  declare patch; patch="$1" && shift
  declare vcs; vcs="$1" && shift
  declare type; type="$1"
  [ ! -e "$patch" ] && \
    { echo "[error] invalid patch file '$patch'" 1>&2 && return 1; }
  [ -z "$(echo "$type" | sed -n '/^\(date\|id\|description\|comments\|files\)$/p')" ] && \
    { echo "[error] invalid info type '$type'" 1>&2 && return 1; }
  [ -z "$(echo "$vcs" | sed -n '/\(git\|subversion\)/p')" ] && \
    { echo "[error] unsupported repository type '$vcs'" 1>&2 && return 1; }
  case "$type" in
    "date")
      case "$vcs" in
        "git"|"subversion") date -d "$(sed -n 's/^Date:[ ]*\(.*\)$/\1/p' "$patch")" '+%s' && return ;;
      esac
      ;;
    "id")
      case "$vcs" in
        "git") sed -n 's/^From[ ]*\([0-9a-f]\{40\}\).*/\1/p' "$patch" && return ;;
        "subversion") sed -n 's/^Revision[: ]*\([r0-9]\+\)$/\1/p' "$patch" && return ;;
      esac
      ;;
    "description")
      case "$vcs" in
        "git") sed -n 's/^Subject:[ ]*\(.*\)$/\1/p' "$patch" && return ;;
        "subversion") sed -n 's/^Subject:[ ]*\(.*\)$/\1/p' "$patch" | sed -n "$RX_COMMITS_DESCRIPTION"'p' && return ;;
      esac
      ;;
    "comments")
      case "$vcs" in
        "git") sed -n '/^Subject/,/^\-\-\-/{/^\-\-\-/{x;s/Subject[^\n]*//;s/^\n*//;s/\n/\\n/g;p;b;};H;b;}' "$patch" && return ;;
        "subversion")
          description="$(fn_patch_info "$patch" "$vcs" "description")"
          comments_="$(sed -n '/^Subject/,/^Index: /{/^Index: /{x;s/Subject: //;s/^\n*//;s/\n/\\n/g;p;b;};H;b;}' "$patch")"
          echo -E "${comments_:${#description}}" | sed 's/^[. ]*\(\\n\)*//;s/\(\\n\)*$//' && return ;;
      esac
      ;;
    "files")
      case "$vcs" in
        "git"|"subversion") sed -n '/^diff/{N;/^diff.*\nindex/{n;N;s/^--- \(.*\)[ ]*\n+++ \(.*\)[ ]*$/\1|\2/p;};}' "$patch" && return ;;
      esac
      ;;
  esac
  return 1
}

fn_commits() {
  declare option; option="commits"

  declare source
  declare src_type
  declare src_type_default; src_type_default="auto"
  declare target
  declare target_fq
  declare limit; limit=0  # unlimited
  declare filter; filter=0
  declare -a filters
  declare repo_maps; repo_maps=0
  declare -a repo_map
  declare repo_map_path; repo_map_path=""
  declare multi_repo_maps; multi_repo_maps=0
  declare -a multi_repo_map
  declare multi_repo_map_default; multi_repo_map_default="fix,mod,hack"
  declare repos
  declare vcs
  declare vcs_source
  declare vcs_target
  declare vcs_default; vcs_default="git"
  declare -a vcs_supported; vcs_supported=("git" "subversion")
  declare -a patch_set
  declare -a commits
  declare commits_
  declare l_commits
  declare -a files
  declare order; order="default"
  declare dump; dump=0
  declare readme; readme="README.md"
  declare readme_status; readme_status=""
  declare readme_status_default; readme_status_default="pending"
  declare auto_commit
  declare interactive_match; interactive_match=0
  declare description
  declare name
  declare type
  declare res
  declare res2
  declare l
  declare v
  declare f

  declare -A vcs_cmds_init
  vcs_cmds_init["git"]="git init"

  # process args
  declare arg
  while [ -n "$1" ]; do
    arg="$(echo "$1" | sed 's/^\ *-*//')"
    if [ ${#1} -gt ${#arg} ]; then
      case "$arg" in
        "st"|"source-type")
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          [ -z "$s" ] && continue  # no shift
          src_type="$s"
          ;;
        "l"|"limit")
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?\([0-9]\+\)$/\1/p;}')"
          limit="${s:-1}"
          [ -z "$s" ] && continue  # no shift
          ;;
        "f"|"filter")
          filter=1
          shift
          filters[${#filters[@]}]="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          ;;
        "rm"|"repo-map")
          repo_maps=1
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          [ -z "$s" ] && continue  # no shift
          IFS=","; repo_map=($(echo "$s")); IFS="$IFSORG"
          ;;
        "mrm"|"multi-repo-map")
          multi_repo_maps=1
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          IFS=","; multi_repo_map=($(echo "${s:-$multi_repo_map_default}")); IFS="$IFSORG"
          [ -z "$s" ] && continue  # no shift
          ;;
        "vcs"|"version-control-system")
          shift
          vcs="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          ;;
        "d"|"dump")
          dump=1
          ;;
        "o"|"order")
          shift
          order="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          ;;
        "im"|"interactive-match")
          interactive_match=1
          ;;
        "rn"|"readme-name")
          shift
          readme="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          ;;
        "rs"|"readme-status")
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          readme="${s:-$readme_status_default}"
          [ -z "$s" ] && continue  # no shift
          ;;
        "nr"|"no-readme")
          readme=""
          ;;
        "ac"|"auto-commit")
          auto_commit="auto"
          shift && s="$(echo "$1" | sed -n '/^[^-]/{s/=\?\(auto\|verify\)/\1/p;}')"
          [ -z "$s" ] && continue  # no shift
          auto_commit="$s"
          ;;
      esac
    else
      if [ -z "$target" ]; then
        target="$1"
      elif [ -z "$source" ]; then
        source="$target"
        target="$1"
      else
        help "$option" && echo "[error] unknown arg '$1'" 1>&2 && return 1
      fi
    fi
    shift
  done

  # validate args

  if [ -n "$vcs" ]; then
    vcs_source="${vcs%|*}"
    vcs_target="${vcs#*|}"
    s="$(fn_str_join "\|" "${vcs_supported[@]}")"
    [ -z "$(echo "$vcs_source" | sed -n '/\('"$s"'\)/p')" ] && \
      echo "[error] unsupported vcs source type: '$vcs_source'" 1>&2 && return 1
    [ -z "$(echo "$vcs_target" | sed -n '/\('"$s"'\)/p')" ] && \
      echo "[error] unsupported vcs target type: '$vcs_target'" 1>&2 && return 1
  fi

  s="$(echo "${src_type:-$src_type_default}" | sed -n 's/^\(auto\|vcs\|dir\|patch\|diff\)$/\1/p')"
  [ -z "$s" ] && \
    { echo "[error] unknown source type '$src_type', aborting" 1>&2 && return 1; }
  src_type="$s"
  source="${source:="."}"
  v=0

  if [[ $v -eq 0 && -f "$source" ]]; then
    [ -z "$(echo "$src_type" | sed -n '/\(patch\|diff\|auto\)/p')" ]
      { echo "[error] invalid source, found file, required '$src_type', aborting" 1>&2 && return 1; }
    src_type="diff"
    v=1
  elif [ -d "$source" ]; then
    [ -z "$(echo "$src_type" | sed -n '/^\(vcs\|dir\|auto\)$/p')" ] && \
      { echo "[error] invalid source, found directory, required '$src_type', aborting" 1>&2 && return 1; }
    if [[ "x$src_type" == "xvcs" || "x$src_type" == "xauto" ]]; then
      vcs_source_="$(fn_repo_type "$source")"
      res=$?
      if [ $res -eq 0 ]; then
        src_type="vcs"
        [[ -n "$vcs_source" && "x$vcs_source" != "x$vcs_source_" ]] && \
          echo "[error] expected source vcs type '$vcs_source' but found '$vcs_source_', aborting" 1>&2 && return 1
        vcs_source="$vcs_source_"
        v=1
      elif [[ $res -eq 1 && "x$src_type" == "xvcs" ]]; then
        echo "[error] unknown vcs type for source directory '$source', aborting" 1>&2 && return 1
      fi
    fi
    if [ $v -eq 0 ]; then
      src_type="dir"
      v=1
    fi
  fi
  if [ $v -eq 0 ]; then
    [ -z "$source" ] && \
      echo "[error] missing '$source', aborting" 1>&2 || \
      echo "[error] invalid source '$source', aborting" 1>&2
    return 1
  fi

  target="${target:="."}"
  if [ ! -d "$target" ]; then
    if [ -z "$target" ]; then
      echo "[error] missing '$target' directory, aborting" 1>&2 && return 1
    else
      fn_decision "[user] create target '$target'?" 1>/dev/null || return 1
      mkdir -p "$target" || return 1
    fi
  fi
  target_fq="$(cd "$target" && pwd)"

  vcs_source="${vcs_source:-"$vcs_default"}"
  vcs_target="${vcs_target:-"$vcs_default"}"
  if [ $dump -eq 0 ]; then
    # repo(s) structure
    declare vcs_
    [ $multi_repo_maps -eq 0 ] && \
      repos=("") || \
      repos=("${multi_repo_map[@]}")

    for repo in "${repos[@]}"; do
      [ "x$(dirname "$repo")" = "x." ] && repo="$target/$repo"
      [ $DEBUG -ge 1 ] && echo "[debug] initialising repo: $repo" 1>&2
      [ ! -d "$repo" ] && { mkdir -p "$repo" || return 1; }
      vcs_target_="$(fn_repo_type "$repo")"
      if [ -n "$vcs_target_" ]; then
        [[ -n "$vcs_target" && "x$vcs_target" != "x$vcs_target_" ]] && \
          echo "[error] expected target vcs type '$vcs_target' but found '$vcs_target_', aborting" 1>&2 && return 1
      else
        fn_decision "[user] initialise "$vcs_target" repo at target directory '$repo'?" 1>/dev/null || return 1
        init="${vcs_cmds_init[$vcs_target]}"
        [ -z "$init" ] && \
          echo "[error] unsupported repository type, missing 'init' command" 1>&2 && return 1
        (cd "$repo" && $init)
      fi
    done
  fi

  [ -z "$(echo "$order" | sed -n '/^\(default\|date\)$/p')" ] && \
    { help "$option"; echo "[error] invalid order '$order'" 1>&2; return 1; }

  # identify patch set
  declare target_fqn
  declare target_fqn_
  declare commit
  declare dt
  declare id
  declare d_tmp_source
  case "$src_type" in
    "vcs")
      commits_="$(fn_repo_search "$source" $limit "${filters[@]}")" 1>&2 || return 1
      [ "x$order" = "xdate" ] && echo -e "$commits_" | sort
      IFS=$'\n'; commits=($(echo "${commits_[@]}")); IFS="$IFSORG"
      l_commits=${#commits[@]}
      d_tmp_source="$(fn_temp_dir "$SCRIPTNAME")"
      temp_data[${#temp_data[@]}]="$d_tmp_source"
      l=0
      for commit in "${commits[@]}"; do
        IFS="|"; parts=($(echo "$commit")); IFS="$IFSORG"
        id="${parts[1]}"
        [ $DEBUG -ge 2 ] && echo "[debug] adding commit '$id' to info cache" 1>&2
        commits_info["$id"]="$commit"
        description="$(echo "${parts[3]}" | sed -n "1${RX_COMMITS_DESCRIPTION}p")"
        name="$(fn_patch_name "$(printf "%0${#l_commits}d" $l)_$id_$description")"
        target_fqn="$d_tmp_source/$name"
        fn_repo_pull "$source" "$id|$target_fqn" || return 1
        patch_set[$l]="$target_fqn"
        l=$((l + 1))
      done
      [[ $repo_maps -eq 1 && ${#repo_map[@]} -eq 0 ]] && \
        repo_map=("$(basename "$(cd "$source" && pwd)")")
      ;;
    "dir")
      IFS=$'\n'; files=($(find "$source" -maxdepth 5 -type "f" | grep -P ".*\.(diff|patch)\$")); IFS="$IFSORG"
      if [ "x$order" = "xdate" ]; then
        s=""
        for f in "${files[@]}"; do
          dt="$(fn_patch_info "$f" "$vcs_source" "date")" || return 1
          s="$s\n$dt|$f"
        done
        IFS=$'\n'; files=($(echo -e "${s:2}" | sort | sed 's/^[^|]\+|//')); IFS="$IFSORG"
      fi
      for f in "${files[@]}"; do
        v=1
        for s in "${filters[@]}"; do
          [ -z "$(echo "f" | grep "$s")" ] && v=0 && break
        done
        if [ $v -eq 1 ]; then
          patch_set[${#patch_set[@]}]="$f"
          [ ${#patch_set[@]} -eq $limit ] && break
        fi
      done
      ;;
    "patch"|"diff")
      patch_set=("$source")
      ;;
  esac
  echo "[info] identified ${#patch_set[@]} patch$([ ${#patch_set[@]} -ne 1 ] && echo "es")"
  [ $DEBUG -ge 1 ] && { for f in "${patch_set[@]}"; do echo "$f"; done; }

  # process patch set
  declare -a parts
  declare entry_description
  declare entry_version
  declare entry_ref
  declare entry_comments
  declare entry_orig
  declare entry_new
  declare readme_search_base
  declare readme_search_category
  declare f_readme
  declare f_tmp
  declare f_new
  declare -a commit_set
  declare decision_opts
  declare opt_string
  declare opt_keys
  declare opt_keys_
  declare existing_
  declare -a existing
  declare -A matched_files
  declare -A info_orig
  declare -A info_new
  declare repo_map_
  declare repo_root
  declare name_
  declare files_
  declare name__
  declare idx
  declare new
  declare s_

  for f in "${patch_set[@]}"; do
    [ $DEBUG -ge 1 ] && echo -e "\n[debug] processing patch: '$f'" 1>&2

    id="$(fn_patch_info "$f" "$vcs_source" "id")" || return 1
    dt="$(fn_patch_info "$f" "$vcs_source" "date")" || return 1
    description="$(fn_patch_info "$f" "$vcs_source" "description")" || return 1
    name="$(fn_patch_name "$description")" || return 1
    commit_set=()

    if [ $dump -eq 1 ]; then
      target_fqn="$target_fq/$name"
      target_fqn_="$(fn_next_file "$target_fqn" "_" "diff")"
      [ "x$target_fqn_" != "x$target_fqn" ] && \
        echo "[info] name clash for: '$target_fqn'"
      cp "$f" "$target_fqn_"
    else

      # set patch target
      ## multi-map / type
      type=""
      if [ ${#repos[@]} -gt 1 ]; then
        decision_opts="$(fn_decision_options "${repos[*]} exit" 1 "exit|x")"
        opt_string="${decision_opts%|*}"
        opt_keys=($(echo "${decision_opts#*|}"))
        opt_keys_="$(fn_str_join "|" "${opt_keys[@]}")"
        res="$(fn_decision "[user] set patch type. $opt_string" "$opt_keys_")"
        [ "x$res" = "xx" ] && return 1
        idx=0
        for k in ${opt_keys[@]}; do
          [ "x$res" = "x$k" ] && break
          idx=$(($idx + 1))
        done
        type="${repos[$idx]}"
      fi
      ## repo map path / categories
      repo_map_path=""
      repo_map_=""
      if [ $repo_maps -eq 1 ]; then
        if [ ${#repo_map[@]} -eq 0 ]; then
          repo_map_="$(basename "$(cd "$(dirname "$f")" && pwd)")"
          repo_map_path="$(fn_escape "path" "$repo_map_")"
        else
          repo_map_path="$(fn_escape "path" "$(fn_str_join "/" "${repo_map[@]}")")"
          repo_map_="$(fn_escape "sed" "$(fn_str_join "|" "${repo_map[@]}")")"
        fi
      fi

      [ $DEBUG -ge 5 ] && echo "[debug] type: $type, categories: ${repo_map[*]}"
      mkdir -p "$target_fq/$type/$repo_map_path"

      # push patch
      target_fqn="$(echo "$target_fq/$type/$repo_map_path/$name" | sed 's/\(\/\)\/\+/\1/g')"
      new=1
      existing_="$(find "$(echo "$target_fq/$type/$repo_map_path/" | sed 's/\(\/\)\/\+/\1/g')" | grep -P '.*\/'"$(fn_escape "perl" "${name%.*}")"'(:?_[0-9]+)?\.diff')"
      existing=()
      [ -n "$existing_" ] &&
        { IFS=$'\n'; existing=($(echo -e "$existing_")); IFS="$IFSORG"; }
      [ $DEBUG -ge 5 ] && \
        echo "[debug] matched ${#existing[@]} existing file$([ ${#existing[@]} -ne 1 ] && echo "s") for patch '$name'"
      entry_version=""
      if [ ${#existing[@]} -gt 0 ]; then
        # name clash or update? find existing
        f_new="$(fn_temp_file "$SCRIPTNAME")"
        cp "$f" "$f_new"
        info_new=()
        info_new["id"]="$(fn_patch_info "$f_new" "$vcs_source" "id")" || return 1
        info_new["date"]="$(fn_patch_info "$f_new" "$vcs_source" "date")" || return 1
        info_new["files"]="$(fn_patch_info "$f_new" "$vcs_source" "files")" || return 1
        info_orig=()
        for f_orig in "${existing[@]}"; do
          # info
          info_orig["id"]="$(fn_patch_info "$f_orig" "$vcs_source" "id")" || return 1
          if [ "x${info_new["id"]}" = "x${info_orig["id"]}" ]; then
            [ $DEBUG -ge 5 ] && echo "[debug] matched on id" 1>&2
            new=-1
          else
            # something has changed..
            info_orig["date"]="$(fn_patch_info "$f_orig" "$vcs_source" "date")" || return 1
            if [ "x${info_new["date"]}" = "x${info_orig["date"]}" ]; then
              # odds are too small for this to be different
              [ $DEBUG -ge 5 ] && echo "[debug] matched on date" 1>&2
              new=0
            else
              info_orig["files"]="$(fn_patch_info "$f_orig" "$vcs_source" "files")" || return 1
              if [ ${#info_new_files[@]} -eq ${#info_orig_files[@]} ]; then
                s_=1
                for l in $(seq 0 1 $((${info_files_orig[@]} - 1))); do
                  [ "x${info_new_files[$l]}" != "x${info_orig_files[$l]}" ] && \
                    { s_=0 && break; }
                done
                [ $s_ -eq 1 ] && matched_files["$f_orig"]=1
              fi
            fi
          fi
          if [ $new -le 0 ]; then
            target_fqn="$f_orig"
            name="$(basename "$target_fqn")"
            [ $new -eq -1 ] && break
            commit_set=("$target_fqn")
            break
          fi
        done
        if [[ $new -eq 1 && $interactive_match -eq 1 ]]; then
          # review interactively
          echo -e "\n${clr["hl"]}target${clr["off"]}|$target_fq/$type/$repo_map_path\n"
          name_="${name%.*}"
          name__="$(fn_escape "sed" "$name_")"
          echo -e "[info] name clash for '$(echo "$name" | sed 's/'"$name__"'/'"\\${clr["hl"]}$name_\\${clr["off"]}"'/')', insufficient certainty to proceed:\n"
##          echo -e "[info] name clash for '$(echo "$name" | sed 's/'"$name__"'/'"pandas"'/')', insufficient certainty to proceed:\n"
          files_=""
          l=1
          for s_ in "${existing[@]}"; do
            files_="$files_\n[$l] $(echo -E "$s_" | sed 's/'"$name__"'/'"\\${clr["hl"]}$name_\\${clr["off"]}"'/')"
            [ -n "${matched_files["$s_"]}" ] && files_="${files_}*"
            l=$((l + 1))
          done
          files_="${files_:2}"
          while true; do
            echo -e "$files_\n"
            [ ${#matched_files[@]} -gt 0 ] && \
              echo -e "*contains matching file set\n"
            res="$(fn_decision "[user] take (d)iff, (s)elect, assume (n)ew, or e(x)it" "d|s|n|x")"
            case "$res" in
              "d")
                while true; do
                  res2="$(fn_edit_line "" "[user] diff against # [1-${#existing[@]}], or e(x)it: ")"
                  res2=$(echo "$res2" | sed -n 's/^[ 0]*\(x\|[^0][0-9]*\)[ ]*$/\1/p')
                  if [ "x$res2" = "xx" ]; then
                    break
                  elif [ $res2 -le ${#existing[@]} ]; then
                    echo
                    diff -u --color=always "${existing[$((res2 - 1))]}" "$f_new" | less -R
                    break
                  fi
                done
                ;;
              "s")
                while true; do
                  res2="$(fn_edit_line "" "[user] select # [1-${#existing[@]}] or e(x)it: ")"
                  res2=$(echo "$res2" | sed -n 's/^[ 0]*\(x\|[^0][0-9]*\)[ ]*$/\1/p')
                  if [ "x$res2" = "xx" ]; then
                    break
                  elif [ $res2 -le ${#existing[@]} ]; then
                    new=0
                    target_fqn="${existing[$((res2 - 1))]}"
                    name="$(basename "$target_fqn")"
                    break
                  fi
                done
                [ $new -eq 0 ] && break
                ;;
              "n") break ;;
              "x") return 1 ;;
            esac
          done
        fi
        if [ $new -eq 0 ]; then
          [ $DEBUG -ge 1 ] && echo "[debug] '$name' target exists, updating '$target_fqn'" 1>&2
          cp "$f_new" "$target_fqn"
          commit_set=("$target_fqn")
        elif [ $new -eq 1 ]; then
          target_fqn="$(fn_next_file "${existing[$((${#existing[@]} - 1))]}" "_" "diff")"
          name="$(basename "$target_fqn")"
          [ $DEBUG -ge 5 ] && echo "[debug] '$name' target exists, pushing to '$target_fqn'"
          cp "$f_new" "$target_fqn"
          commit_set=("$target_fqn")
        fi
      else
        new=1
        [ $DEBUG -ge 1 ] && echo "[debug] '$name' target is new, pushing to '$target_fqn'" 1>&2
        cp "$f" "$target_fqn"
        commit_set=("$target_fqn")
      fi
      entry_version="$(echo "$name" | sed -n 's/.*_\([0-9]\+\).diff/ #\1/p')"

      if [ -n "$readme" ]; then
        case "$vcs_source" in
          "git")
            readme_search_category="${info_orig["id"]}"
            readme_search_base="${readme_search_category:0:9}"
            ;;
          "subversion")
            readme_search_category="$(echo "${info_orig["id"]}" | sed 's/^r//')"
            readme_search_base="$readme_search_category"
            ;;
          *)
            echo "[error] unsupported repository type" 1>&2 && return 1
            ;;
        esac
        entry_description="$description"
        if [ -n "$repo_map_" ]; then
          # append patch info to readme at base of repo
          f_readme="$(echo "$target_fq/$type/$readme" | sed 's/\(\/\)\/\+/\1/g')"
          entry_ref=""
          case "$vcs_source" in
            "git") entry_ref="[git sha:${id:0:9}]" ;;
            "subversion") entry_ref="[svn rev:${id#r}]" ;;
            *) echo "[error] unsupported repository type" 1>&2 && return 1 ;;
          esac
          entry_new="$entry_description$entry_version $entry_ref"
          [ ! -e "$f_readme" ] && \
            echo -e "### ${type:-$(basename "$target_fq")}" >> "$f_readme"
          # search for existing entry
          if [ -z "$(sed -n '/^#### \['"$repo_map_"'\]('"$repo_map_"')$/p' "$f_readme")" ]; then
            # add entry
            echo -e "\n#### [$repo_map_]($repo_map_)\n"'```'"\n$entry_new\n"'```' >> "$f_readme"
            commit_set[${#commit_set[@]}]="$f_readme"
          else
            # insert entry?
            entry_orig=""
            if [ -n "$readme_search_base" ]; then
              entry_orig="$(sed -n '/^#### \['"$repo_map_"'\]('"$repo_map_"')$/,/\(^$|$\)/{/'"$(fn_escape "sed" "$readme_search_base")"'/{p;};}' "$f_readme")"
            fi
            if [[ -z "$entry_orig" ]]; then
              # insert at end
              sed -n -i '/^#### \['"$repo_map_"'\]('"$repo_map_"')$/,/$^/{/^#### \['"$repo_map_"'\]('"$repo_map_"')$/{N;h;b};/^```$/{x;s/\(.*\)/\1\n'"$(fn_escape "sed" "$entry_new")"'\n```/p;b;}; H;$!b};${x;/^#### ['"$repo_map_"'\]('"$repo_map_"')/{s/\(.*\)/\1\n'"$(fn_escape "sed" "$entry_new")"'/p;b;};x;p;b;};p' "$f_readme"
              commit_set[${#commit_set[@]}]="$f_readme"
            elif [ "x$entry_new" != "x$entry_orig" ]; then
              # update
              f_tmp="$(fn_temp_file)"
              if [ $DEBUG -ge 5 ]; then
                cp "$f_readme" "$f_tmp"
                echo -e "[debug] root readme comparison:" \
                        "\n-- original --\n$entry_orig" \
                        "\n-- new --\n$entry_new\n--"
              fi
              sed -i '/^#### \['"$repo_map_"'\]('"$repo_map_"')$/,/^$/{s/'"$(fn_escape "sed" "$entry_orig")"'/'"$entry_new"'/;}' "$f_readme"
              if [ $DEBUG -ge 5 ]; then
                echo -e "\n readme diff:"
                diff -u --color=always "$f_readme.orig" "$f_tmp"
                echo ""
                rm "$f_tmp" 2>/dev/null
              fi
              commit_set[${#commit_set[@]}]="$f_readme"
            fi
          fi
        fi
        # append patch details to category specific readme
        f_readme="$(echo "$target_fq/$type/$repo_map_path/$readme" | sed 's/\(\/\)\/\+/\1/g')"
        entry_ref=""
        case "$vcs_source" in
          "git") entry_ref="[git sha:$id$([ -n "$readme_status" ] && echo " | $readme_status")]" ;;
          "subversion") entry_ref="[svn rev:${id#r}$([ -n "$readme_status" ] && echo " | $readme_status")]" ;;
          *) echo "[error] unsupported repository type" 1>&2 && return 1 ;;
        esac
        entry_comments="$(fn_patch_info "$target_fqn" "$vcs_source" "comments")" || return 1
        entry_new="##### $entry_description$entry_version\n###### $entry_ref$([ -n "$entry_comments" ] && echo "\n"'```'"\n$entry_comments\n"'```')"
        [ ! -e "$f_readme" ] && \
          echo "### ${repo_map_:-$(basename "$target_fq")}" >> "$f_readme"

        # search for existing entry
        entry_orig=""
        if [ -n "$readme_search_category" ]; then
          entry_orig="$(awk -v "id=$(fn_escape "awk" "$readme_search_category")" '
function fn_test(data) {
  if (section ~ ".*"id".*") {
    gsub(/\n/, "\\n", data);
    gsub(/\\n$/, "", data);
    print data;
  }
}
BEGIN { section="" }
{
  if ($0 ~ "^##### .*") {
    if (section != "")
      fn_test(section);
    section = $0;
  } else
    section = section"\\n"$0
}
END { fn_test(section); }' "$f_readme")"
        fi
        if [[ -z "$entry_orig" || $new -eq 1 ]]; then
          # insert at end
          echo -e "\n$entry_new" >> "$f_readme"
          commit_set[${#commit_set[@]}]="$f_readme"
        elif [ "x$entry_new" != "x$entry_orig" ]; then
          # update
          f_tmp="$(fn_temp_file)"
          if [ $DEBUG -ge 5 ]; then
            cp "$f_readme" "$f_tmp"
            echo -e "[debug] root readme comparison:" \
                    "\n-- original --\n$entry_orig" \
                    "\n-- new --\n$entry_new\n--"
          fi
          sed -n -i '1h;1!H;${x;s/'"$(fn_escape "sed" "$entry_orig")"'/'"$entry_new"'/;p;}' "$f_readme"
          if [ $DEBUG -ge 5 ]; then
            echo -e "\n readme diff:"
            diff -u --color=always "$f_tmp" "$f_readme"
            echo ""
            rm "$f_tmp" 2>/dev/null
          fi
          commit_set[${#commit_set[@]}]="$f_readme"
        fi
      fi

      # commit
      [ ${#commit_set[@]} -eq 0 ] && \
        echo "[info] no changes to commit" && continue

      echo "[info] commit set:"
      for f in "${commit_set[@]}"; do echo "$f"; done
      if [ -n "$auto_commit" ]; then
        repo_root="$(echo "$target_fq/$type/" | sed 's/\(\/\)\/\+/\1/g')"
        cd "$repo_root" 1>/dev/null
        if [ "x$auto_commit" = "xverify" ]; then
          fn_decision "[user] authored: $(date -d "@$dt" "+%d %b %Y %T %z"), commit set?" 1>/dev/null || return 1
        fi
        for f in "${commit_set[@]}"; do
          f_="./$(echo "$f" | sed 's|^'"$repo_root"'||')"
          git add "$f_" || return 1
        done
        declare commit_message
        commit_message="[$([ $new -eq 1 ] && echo "add" || echo "mod")]$([ -n "$repo_map_" ] && echo " $repo_map_,") $(echo $description$entry_version | sed 's/^\[\([^]]*\)\]/\1,/')"
        GIT_AUTHOR_DATE="$dt" GIT_COMMITTER_DATE="$dt" git commit -m "$commit_message"
        cd - 1>/dev/null
      fi
    fi
  done
  [ $dump -eq 0 ] && \
    echo "# patches added to $([ ${#repos[@]} -eq 1 ] && echo "repo" || echo "'$(fn_str_join "/" "${repos[@]}")' repos") at '$target'$([ -n "$repo_map_path" ] && echo " under '$repo_map_path' hierarchy")"
}

fn_changelog() {
  declare option; option="changelog"

  declare target
  declare target_default="."
  declare vcs
  declare anchor_start; anchor_start=1
  declare profile; profile="default"
  declare file
  declare rx_id
  declare anchor_entry

  declare -A changelog_profiles
  changelog_profiles["default"]=1
  changelog_profiles["update"]=1

  # process args
  declare -a args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-+/,"",$0); print(tolower($0))}')"
    if [ ${#arg} -lt ${#1} ]; then
      # process named options
      case "$arg" in
        "as"|"anchor_start") shift && anchor_start="$1" ;;
        "p"|"profile") shift && profile="$1" ;;
        "f"|"file") shift && file="$1" ;;
        "rxid"|"rx-id") shift && rx_id="$1" ;;
        "ae"|"anchor_entry") shift && anchor_entry="$1" ;;
        *) help "$option" && echo "[error] unrecognised arg '$1'" 1>&2 && return 1 ;;
      esac
    else
      [ -z "$target" ] && \
        target="$1" || \
        help "$option" && echo "[error] unrecognised arg '$1'" 1>&2 && return 1
    fi
    shift
  done

  # validate args
  [ -z "$target" ] && target="$target_default"
  [ -d "$target" ] || \
    { help "$option" && echo "[error] invalid target '$target'" 1>&2 && return 1; }
  vcs="$(fn_repo_type "$target")"
  [ -z "$vcs" ] && echo "[error] unsupported repository type" 1>&2 && return 1
  [ -z "${changelog_profiles["$profile"]}" ] && \
    { help "$option" && echo "[error] invalid profile '$profile'" 1>&2 && return 1; }
  [ -z "$file" ] && file="${changelog_profile_file["$profile"]}"
  [ -z "$rx_id" ] && rx_id="${changelog_profile_rx_id["$profile"]}"
  [ -z "$anchor_entry" ] && anchor_entry="${changelog_profile_anchor_entry["$profile"]}"

  cd "$target"

  declare merge
  declare commit
  declare commit_range;
  declare -a commits
  declare commits_count;
  declare f_tmp; f_tmp="$(fn_temp_file "$SCRIPTNAME")"
  case $vcs in
    "git")
      merge=0
      commit_range="HEAD"
      if [ -f "$file" ]; then
        # merge or clear
        commit="$(sed -n 's/^.*'"$rx_id"'.*$/\1/p' "$file" | head -n1)"
        if [ -z "$commit" ]; then
          if [ $(cat "$file" | wc -l) -gt 0 ]; then
            fn_decision "[user] no commits found with search expression '$rx_id' so target '$file' will be overwritten, continue?" 1>/dev/null || return 0
          fi
          # set range
          rm "$file" && touch "$file"
        else
          # last changelog commit valid?
          if [ -n "$(git log --format=oneline | grep "$commit")" ]; then
            [ $DEBUG -ge 1 ] && echo "[debug] last changelog commit '${commit:0:8}..' validated" 1>&2
            commit_range="$commit..HEAD"
            merge="$(grep -n "$commit" $file | cut -d':' -f1)"
          elif fn_decision "[user] last changelog commit '${commit:0:8}..' unrecognised, search for merge point?" 1>/dev/null; then
            # search
            IFS=$'\n'; commits=($(fn_repo_search "." 0)) || return 1; IFS="$IFSORG"
            declare match
            declare id
            declare description
            for c in "${commits[@]}"; do
              id="$(echo "$c" | cut -d'|' -f2)"
              match="$(grep -n "$id" "$file")"
              if [ -n "$match" ]; then
                merge=${match%%:*}
                match=${match#*:}
                description="$(echo "$c" | cut -d'|' -f3)"
                commit="$id"
                break
              fi
            done
            if [ -n "$commit" ]; then
              echo -e "[info] matched: [${clr["bwn"]}$id${clr["off"]}] $description\n\n'$(echo "$match" | sed 's/'"$id"'/'"$(echo -e "${clr["hl"]}$id${clr["off"]}")"'/')'\n"
              fn_decision "[user] merge with existing changelog at this point?" 1>/dev/null || return 1
              commit_range="$commit..HEAD"
            else
              fn_decision "[user] no merge point identified, clear all existing entries?" 1>/dev/null || return 1
              rm "$file" && touch "$file"
            fi
          fi
          declare merge_start; merge_start=$((merge - anchor_entry))
          if [ $merge_start -gt $anchor_start ]; then
            [ $DEBUG -ge 1 ] && echo "[debug] clearing $((merge_start - anchor_start)) overlapping lines" 1>&2
            sed -i $anchor_start','$merge_start'd' "$file"
          fi
        fi
      fi

      commits_count=$(git log --pretty=oneline "$commit_range" | wc -l)
      touch "$file"
      echo "[info] $commits_count commit$([ $commits_count -ne 1 ] && echo "s") to add to changelog"
      [ $commits_count -eq 0 ] && return 0

      echo "[info] $([ $merge -gt 0 ] && echo "updating" || echo "creating new") changelog"
      head -n$((anchor_start - 1)) "$file" > "$f_tmp"
      case "$profile" in
        "default")
          git log -n $commits_count --pretty=format:"%at version %H%n - %s (%an)" | awk '{if ($1 ~ /[0-9]+/) {printf strftime("%Y%b%d",$1); $1=""} print $0}' >> "$f_tmp"
          ;;
        "update")
          git log -n 1 --pretty=format:"%n#### %at%n## release: %d version: %H" | awk '{if ($2 ~ /[0-9]+/) {$2 = strftime("%Y%b%d",$2)} print $0}' | sed '/release: .\{2,\}version/{/tag/{s/release:.*tag: \([^ )]*\).*version/release: \1 version/;b;};s/release:.*version/release: - version/;b;}' >> "$f_tmp"
          git log -n $commits_count --pretty=format:"- %s ([%an](%ae))" >> "$f_tmp"
          echo "" >> "$f_tmp"
          ;;
      esac
      tail -n+$anchor_start "$file" >> "$f_tmp"
      mv "$f_tmp" "$file"
      ;;
    *)
      echo "[error] vcs type: '$vcs' not implemented" 1>&2 && return 1
      ;;
  esac
}

fn_debug() {
  declare option; option="debug"

  declare supported_languages
  supported_languages="c c++ javascript"

  declare language_default
  declare language
  declare -A debuggers
  declare -A debugger_args
  declare -A debugger_args_template
  declare args_pt

  # c
  debuggers["c"]="gdb"
  debugger_args["c"]="NAME PID _ARGS_"
  debugger_args_template["c"]="NAME PID|--pid=PID _ARGS_"
  # c++
  debuggers["c++"]="gdb"
  debugger_args["c++"]="NAME PID _ARGS_"
  debugger_args_template["c++"]="NAME PID|--pid=PID _ARGS_"
  # javascript
  debuggers["javascript"]="node"
  debugger_args["javascript"]="SRC PORT=9229 _ARGS_"
  debugger_args_template["javascript"]="PORT|--inspect-brk=PORT SRC _ARGS_"

  language_default=c
  args_pt=""
  declare -a args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-+/,"",$0); print(tolower($0))}')"
    if [ ${#arg} -lt ${#1} ]; then
      # process named options
      case "$arg" in
        "l"|"language") shift && language="$1" ;;
        "")
          # pass-through remaining args
          shift
          s="";
          while [ -n "$1" ]; do s="$s $(fn_escape "space" "$1")"; shift; done
          args_pt="${s:1}"
          continue;
          ;;
        *) help "$option" && echo "[error] unrecognised arg '$1'" 1>2 && return 1
      esac
    else
      args[${#args[@]}]="$1"
    fi
    shift
  done

  # validate args
  [[ -n "$language" && \
     -z "$(echo "$language" | \
       sed -n '/^\('"$(echo "$supported_languages" | \
         sed 's/ /\\|/g')"'\)$/p')" ]] && \
    help "$option" && echo "[error] unsupported language '$language'" 1>&2 && return 1

  language=${language:-$language_default}

  declare bin
  declare -a bin_args

  bin="${debuggers["$language"]}"

  _ARGS_=""
  if [ -n "$args_pt" ]; then
    case "$bin" in
      "gdb") _ARGS_="-ex 'set args _ARGS_'" ;;
      *) _ARGS_="-- _ARGS_" ;;
    esac
  fi

  # deduce, consume, or calculate arg values
  args_ns=(${debugger_args["$language"]})
  declare -A arg_vs
  declare args_idx
  args_idx=0
  for arg_n in "${args_ns[@]}"; do
    n="${arg_n%%=*}"
    v="$(eval 'echo "$'$n'"')"
    [[ -z "$v" && -n "${args[$args_idx]}" ]] && \
      v="${args[$args_idx]}" && args_idx=$((args_idx + 1))
    [[ -z "$v" && ${#n} -ne ${#arg_n} ]] && \
      v="${arg_n#*=}"
    # special handling
    case "$n" in
      "_ARGS_")
        [ -n "$args_pt" ] && \
          v="$(echo "$_ARGS_" | sed 's/'"$n"'/'"$(fn_escape "path" "$args_pt")"'/')"
        ;;
      "PID")
        [ -n "$v" ] && continue
        name="${arg_vs["NAME"]}"
        [ -z "$name" ] && continue
        declare proc
        declare select
        select=0
        pgrep="$(which pgrep)"
        if [ -n "$pgrep" ]; then
          IFS=$'\n'; proc=($(pgrep -x -a "$name")); IFS="$IFSORG"
          if [ ${#proc[@]} -eq 0 ]; then
            IFS=$'\n'; proc=($(pgrep -f -a "$name")); IFS="$IFSORG"
            [ ${#proc[@]} -gt 0 ] && select=1  # force
          fi
        else
          pidof="$(which pidof)"
          if [ -z "$pidof" ]; then
            echo "[info] missing pgrep / pidof binaries, cannot" \
                 "identify target process for debugging"
          else
            IFS=$'\n'; proc=($(pidof "$name")); IFS="$IFSORG"
          fi
        fi
        if [[ ${#proc[@]} -gt 1 || $select -eq 1 ]]; then
          opts=""
          lmax="${#proc[@]}"
          llmax=${#lmax}
          pmax="${proc[$((${#proc[@]} - 1))]}"
          p_max="${pmax%% *}"
          lp_max="${#p_max}"
          l=0
          for ps in "${proc[@]}"; do
            ps_="${ps%% *}"
            [ "x$ps_" = "x$$" ] && continue
            l=$((l + 1))
            opts+="|$l"
            printf "%$((llmax - ${#l}))s[%d] %$((lp_max - ${#ps_}))s%s\n" "" $l "" "$ps_ | ${ps#* }"
          done
          if [ $l -gt 0 ]; then
            echo "[info] no exact process matched '$name'" \
                 "full command line search found $l" \
                 "possibilit$([ ${#proc[@]} -eq 1 ] && echo "y" \
                                                    || echo "ies")"
            opts="${opts:1}|x"
            prompt="select item # or e(${clr["hl"]}x${clr["off"]})it "
            prompt+="[${clr["hl"]}1${clr["off"]}"
            [ $l -gt 1 ] && prompt+="-${clr["hl"]}$l${clr["off"]}"
            prompt+="|${clr["hl"]}x${clr["off"]}]"
            res="$(fn_decision "$prompt" "$opts" 0 0 1)"
            if [ "x$res" != "xx" ]; then
              ps="${proc[$((res - 1))]}"
              v="${ps%% *}"
            fi
          fi
        fi
        ;;
    esac
    [ -n "$v" ] && arg_vs["$n"]="$v"
  done
  # replace template placeholders with any available values
  args_ts=(${debugger_args_template["$language"]})
  for arg_t in "${args_ts[@]}"; do
    n="${arg_t%%|*}"
    t="${arg_t#*|}"
    v="${arg_vs["$n"]}"
    [ -n "$v" ] && bin_args[${#bin_args[@]}]="$(echo "$t" | sed 's/'"$n"'/'"$(fn_escape "path" "$v")"'/')"
  done

  # execute
  fn_decision "[user] debug: $bin ${bin_args[*]} ?" >/dev/null || return 0
  eval "$bin ${bin_args[*]}"
}

fn_refactor_header() {
  declare info
  info="$1" && shift
  printf "%s\n%s\n%s\n" $(printf "%.s-" $(seq 1 1 ${#info})) \
                        "${clr["hl"]}"$info"${clr["off"]}" \
                        $(printf "%.s-" $(seq 1 1 ${#info}))
}

fn_refactor() {
  declare option; option="refactor"

  declare -a targets
  declare targets_default
  targets_default="."
  declare filter
  declare depth
  declare modify
  modify=0
  declare -a transforms
  declare -A transforms_valid
  transforms_valid["braces"]="braces"
  transforms_valid["tabs"]="tabs"
  transforms_valid["whitespace"]="whitespace"
  declare transform_default
  transforms_default="tabs whitespace"
  declare xi
  xi=0
  declare xi_profile
  declare -a xi_profiles_valid
  xi_profiles_valid["standard"]="standard"
  declare xi_profile_default
  xi_profile_default="standard"

  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-+/,"",$0); print(tolower($0))}')"
    if [ ${#arg} -lt ${#1} ]; then
      # process named options
      case "$arg" in
        "f"|"filter") shift && filter="$1" ;;
        "d"|"depth") shift && depth="$1" ;;
        "m"|"modify") modify=1 ;;
        "t"|"transforms")
          shift
          declare -a transforms_
          IFS=','; transforms_=($(echo "$1")); IFS="$IFSORG"
          declare -a unrecognised
          for t in "${transforms_[@]}"; do
            [ "x$t" = "xall" ] && transforms=("${transforms_valid[@]}") && break
            [ -n "${transforms_valid["$t"]}" ] && \
              transforms[${#transforms[@]}]="$t" || \
              unrecognised[${#unrecognised[@]}]="$t"
          done
          [[ ${#unrecognised[@]} -gt 0 ]] && \
            echo "[info] dropped unrecognised transform"\
                 "$([ ${#unrecognised[@]} -ne 1 ] && echo "s") '${unrecognised[*]}'"
          ;;
        "xi"|"external-indent")
          shift
          xi=1
          [[ -n "$1" && -n "${xi_profiles_valid["$1"]}" ]] && xi_profile
          ;;
      esac
    else
      [ ! -e "$1" ] && \
        echo "[info] dropping invalid target '$1'" || \
        targets[${#targets[@]}]="$1"
    fi
    shift
  done

  # ensure args
  [ ${#targets[@]} -eq 0 ] && targets=("$targets_default")
  [ -z "$filter" ] && filter=".*"
  [ -z "$depth" ] && depth=1

  # set targets
  IFS=$'\n'; files=($(fn_search_set "$filter" 1 $depth "${targets[@]}")); IFS="$IFSORG"

  # process targets
  if [ $xi -eq 1 ]; then
    # 'GNU indent' wrapper

    [ -z "$(which indent)" ] && \
      echo "[error] no binary 'indent' found on this system" 1>&2 && return 1

    # ensure args
    [ -z "$xi_profile" ] && xi_profile="$xi_profile_default"

    for f in "${files[@]}"; do
      [ $DEBUG -ge 1 ] && echo "[info] processing target file '$f'" 1>&2
      case $xi_profile in
        "standard")
          indent \
            --blank-lines-after-procedures \
            --blank-lines-before-block-comments \
            --braces-on-if-line \
            --braces-on-struct-decl-line \
            --case-indentation 2 \
            --indent-leveln \
            --start-left-side-of-comment \
            --swallow-optional-blank-lines \
            --no-tabs \
            --cuddle-else \
            --cuddle-do-while \
            --space-after-for \
            --space-after-if \
            --space-after-while \
            --space-special-semicolon \
            --no-space-after-function-call-names \
            --no-space-after-parentheses \
            --line-length 120 \
              "$f"
          ;;
      esac
    done

  else
    # custom refactoring

    # ensure args
    [ ${#transforms[@]} -eq 0 ] && transforms=($(echo "$transforms_default"))

    for f in "${files[@]}"; do
      [ $DEBUG -ge 1 ] && echo "[info] processing target file '$f'" 1>&2

      if [ $modify -eq 0 ]; then
        # search only #

        l=0
        for t in "${transforms[@]}"; do
          case "$t" in
            "braces")
              # search for new line character preceding brace
              fn_refactor_header "> searching for 'new line characters preceding braces' in file '$f'"
              sed -n 'H;x;/.*)\s*\n\+\s*{.*/{s/\n/'"$(printf "${clr["red"]}%s${clr["off"]}" "\\\n")"'\n/;p}' "$f"
              ;;
            "tabs")
              # search for tabs characters
              fn_refactor_header "> searching for 'tab characters' in file '$f'"
              sed -n 's/\t/'"${clr["red"]}"'[ ]'"${clr["off"]}"'/gp' "$f"
              ;;
            "whitespace")
              # search for trailing whitespace
              fn_refactor_header "> searching for 'trailing whitespace' in file '$f'"
              IFS=$'\n'; lines=($(sed -n '/\s$/p' "$f")); IFS=$IFSORG
              for line in "${lines[@]}"; do
                echo "$line" | sed -n ':1;s/^\(.*\S\)\s\(\s*$\)/\1\'"$(printf ${clr["red"]})"'·\2/;t1;s/$/\'"$(printf ${clr["off"]})"'/;p'
              done
              ;;
            *)
              printf "${clr["red"]}[error] missing transform '$t'${clr["off"]}\n"
              ;;
          esac
          l=$((l + 1))
          [ $l -ne ${#transforms[@]} ] && printf "\n"
        done

      else
        # persist #

        sedcmd="$([ $TEST -gt 0 ] && echo "echo ")sed"
        l=0
        for t in "${transforms[@]}"; do
          case "$t" in
            "braces")
              # remove new line character preceding brace
              fn_refactor_header "> removing 'new line characters preceding braces' in file '$f'"
              $sedcmd -i -n '1{${p;b;};h;b};/^\s*{/{x;/)\s*$/{x;H;x;s/\s*\n\s*/ /;p;n;x;b;};x;};x;p;${x;p;};' "$f"
              ;;
            "tabs")
              # replace tabs with double spaces
              fn_refactor_header "> replacing 'tab characters' in file '$f'"
              $sedcmd -i 's/\t/  /g' "$f"
              ;;
            "whitespace")
              # remove trailing whitespace
              fn_refactor_header "> removing 'trailing whitespace' in file '$f'"
              $sedcmd -i 's/\s*$//g' "$f"
              ;;
            *)
              printf "${clr["red"]}[error] missing transform '$t'${clr["off"]}\n"
              ;;
          esac
          l=$((l + 1))
          [ $l -ne ${#transforms[@]} ] && printf "\n"
        done

      fi
    done

  fi
}

fn_port() {
  declare option; option="port"

  declare target
  declare type
  declare transforms; transforms="/root/.nixTools/$SCRIPTNAME"
  declare transforms_debug_
  declare -A transforms_debug
  declare -a lines; lines=()
  declare diffs; diffs=0
  declare overwrite; overwrite=0
  declare verify; verify=0
  declare ignore_error; ignore_error=0

  declare from
  declare to

  declare cmd_diff; cmd_diff="$(which "diff")"
  declare -a cmd_args_diff; cmd_args_diff=("-u" "--color=always")

  stdout=1
  [ ! -t $stdout ] && \
    echo "[info] pipe detected, redirecting non-result output to stderr" 1>&2 && stdout=2

  # process args
  [ $# -lt 1 ] && help "$option" && echo "[error] not enough args" 1>&2 && return 1
  while [ -n "$1" ]; do
    arg="$(echo "$1" | sed 's/^[ ]*-*//')"
    if [ ${#arg} -lt ${#1} ]; then
      case "$arg" in
        "x"|"transforms") shift && transforms="$1" ;;
        "xs"|"transforms-source") shift && from="$1" ;;
        "xt"|"transforms-target") shift && to="$1" ;;
        "xd"|"transforms-debug") shift && transforms_debug_="$1" ;;
        "l"|"lines") shift && lines=("$1") ;;
        "d"|"diffs") diffs=1 ;;
        "o"|"overwrite") overwrite="1" ;;
        "v"|"verify") verify=1 ;;
        "ie"|"ignore-errors") ignore_error=1 ;;
        *) help "$option" && echo "[error] unrecognised arg '$1'" 1>&2 && return 1
      esac
    else
      [ -z "$target" ] && \
        target="$1" || \
        { help "$option" && echo "[error] unrecognised arg '$1'" 1>&2 && return 1; }
    fi
    shift
  done

  # validate args
  [ ! -f "$target" ] && \
    echo "[error] invalid target file '$target'" 1>&2 && return 1
  [ ! -f "$transforms" ] && \
    echo "[error] invalid transforms file '$transforms'" 1>&2 && return 1
  type="${target##*.}"
  from="${from:-$type}"
  to="${to:-$type}"
  if [ ${#lines[@]} -gt 0 ]; then
    declare -a ranges; IFS=","; ranges=($(echo "${lines[0]}")); IFS="$IFSORG"
    declare lines_
    lines=()
    for range in "${ranges[@]}"; do
      lines_="$(echo "$range" | sed -n 's/^\([0-9]\+\)[^0-9]\+\([0-9]*\)$/\1,\2/p')"
      [ -z "$lines_" ] && lines_="$(echo "$range" | sed -n 's/^\([0-9]\+\)$/\1/p')"
      [ -z "$lines_" ] && echo "[error] invalid lines range '$range'" 1>&2 && return 1
      lines[${#lines[@]}]="$lines_"
    done
  else
    lines=("")  # stub
  fi
  if [ -n "$transforms_debug_" ]; then
    diffs=0
    declare -a transforms_debug__; IFS=","; transforms_debug__=($(echo "${transforms_debug_}")); IFS="$IFSORG"
    declare l
    for l in "${transforms_debug__[@]}"; do
      [ -z "$(echo "$l" | sed -n '/^\([0-9]\+\)$/p')" ] && \
        echo "[error] invalid transform debug line number: '$l'" 1>&2 && return 1
      transforms_debug["$l"]=1
    done
  fi
  [[ $diffs -eq 1 && ! -x "$cmd_diff" ]] && \
    echo "[error] no diff binary found'" 1>&2 && return 1

  [ $DEBUG -ge 1 ] && echo "[debug] type: $type, xs|from: $from, xt|to: $to" 1>&2

  f_tmp="$(mktemp)"
  f_tmp2="$(mktemp)"
  f_tmp3="$(mktemp)"
  cp "$target" "$f_tmp"

  declare line
  declare diff_
  declare -a maps
  declare -a transforms_
  declare line
  declare l_line; l_line=0
  declare debug
  declare match
  declare match_
  declare expr_
  declare break_
  declare res
  declare skip; skip=0
  declare process; process=1
  declare l_total; l_total=0
  declare l_processed; l_processed=0
  declare l_diffs; l_diffs=0
  declare mod_repeat
  IFS=$'\n'; transforms_=($(sed -n 'p' "$transforms")); IFS="$IFSORG"
  while read -r line; do
    l_line=$((l_line + 1))
    # skip blanks and comments
    [ -z "$(echo "$line" | sed '/\(^$\|^[ ]*#\)/d')" ] && continue
    debug=0 && [ -n "${transforms_debug["$l_line"]}" ] && debug=1
    [ $DEBUG -ge 5 ] && echo "[debug] line $l_line: '$line', process: $process, skip: $skip, debug: $debug" 1>&2
    [ $skip -eq 1 ] && skip=0 && process=1 && continue
    if [ $process -eq 1 ]; then
      l_total=$((l_total + 1))
      [ -z "$(echo "$line" | sed -n '/|/p')" ] &&
        echo "[error] invalid mappings line ${clr["hl"]}${l_line}${clr["off"]}, '$line'" 1>&2 && return 1

      # strip inline comments and tokenise on whitespace
      ss=($(echo "${line%% #*}"))
      match_=0
      skip=1
      mod_repeat=0
      for s in "${ss[@]}"; do
        case "${s%|*}" in
          "%") # modifiers
            case "${s#*|}" in
              "repeat") mod_repeat=1 ;;
            esac
            ;;
          *) # maps
            [ $match_ -eq 1 ] && continue
            match_=1
            f="${s%|*}"
            t="${s#*|}"
            [[ "x$f" != "x*" && "x$f" != "x$from" ]] && match_=0
            [[ "x$t" != "x*" && "x$t" != "x$to" ]] && match_=0
            [ $match_ -eq 1 ] && process=1
            if [ $match_ -eq 1 ]; then
              match="$(echo "$line" | sed 's/'"$(fn_escape "sed" "$s")"'/'"${clr["hl"]}$s${clr["off"]}"'/')"
              skip=0
              l_processed=$((l_processed + 1))
            fi
            ;;
        esac
      done
      [ $DEBUG -ge 5 ] && echo "[debug] processed, match: $match_, skip: $skip" 1>&2
      process=0
    elif [ $skip -eq 0 ]; then
      # apply transform
      process=1  # next
      [ $DEBUG -ge 1 ] && echo -e "[debug] applying match: $match, transform: '$line'" 1>&2
      cp "$f_tmp" "$f_tmp2"
      for range in "${lines[@]}"; do
        [ $DEBUG -ge 3 ] && echo "[debug] line range: '$range'" 1>&2
        expr_="$range{$line;}"
        while true; do
          if [ $debug -eq 1 ]; then
            echo "[debug] ${clr["hl"]}source:${clr["off"]}" 1>&$stdout
            echo "${clr["grn"]}" 1>&$stdout
            sed -n "$range{p;}" "$f_tmp2" 1>&$stdout
            echo "${clr["off"]}" 1>&$stdout
            set -x && sed "$expr_" "$f_tmp2" > "$f_tmp3" && set +x
            res=$?
          else
            sed "$expr_" "$f_tmp2" > "$f_tmp3"
            res=$?
          fi
          [ $res -ne 0 ] && break
          [[ $mod_repeat -eq 0 || \
             -z "$(diff "$f_tmp2" "$f_tmp3")" ]] && break
          mv "$f_tmp3" "$f_tmp2"
        done
        # error
        if [ $res -ne 0 ]; then
          echo "[error] processing line ${clr["hl"]}${l_line}${clr["off"]}, expression '${clr["red"]}$expr_${clr["off"]}'" 1>&2
          [ $ignore_error -eq 1 ] && continue || return 1
        fi
        cp "$f_tmp3" "$f_tmp2"
      done
      diff_="$($cmd_diff "${cmd_args_diff[@]}" "$f_tmp" "$f_tmp3")"
      if [ -n "$diff_" ]; then
        if [ $verify -eq 1 ]; then
          s="[user] apply modifying transform '${clr["grn"]}$line${clr["off"]}?'"
          break_=0
          while true; do
            res="$(fn_decision "$s (y)es, (n)o, show (d)iff or e(x)it" "y|n|d|x")"
            case "$res" in
              "y") break ;;
              "n") break_=1; break ;;
              "x") return 1 ;;
              "d") $cmd_diff "${cmd_args_diff[@]}" "$f_tmp" "$f_tmp3" 1>&$stdout ;;
            esac
            echo -en "$CUR_UP$LN_RST" 1>&2
          done
          [ $break_ -eq 1 ] && continue
        fi
        l_diffs=$((l_diffs + 1))
      fi
      if [[ ( -n "$diff_" && $diffs -eq 1 ) || $debug -eq 1 ]]; then
        echo -n "[info] match: $match, transform: '$line' applied, diff:" 1>&2
        [ -n "$diff_" ] && \
          echo -e $"\n$diff_" 1>&$stdout || \
          echo " no difference" 1>&$stdout
      fi
      [ $DEBUG -ge 1 ] && echo -e "[debug] post transform line count: $(cat "$f_tmp3" | wc -l)" 1>&2
      cp "$f_tmp3" "$f_tmp"
    fi
  done < $transforms

  rm "./results" 2>/dev/null
  diff_="$($cmd_diff "${cmd_args_diff[@]}" "$target" "$f_tmp")"
  if [ -n "$diff_" ]; then
    if [ $diffs -eq 1 ]; then
      echo -e "$diff_" 1>&$stdout
    elif [[ $overwrite -eq 0 && -z "$transforms_debug_" && -t 1 ]]; then
      cp "$f_tmp" "./results"
      echo "[info] results modified './results' target" 1>&$stdout
    fi
    if [ $overwrite -eq 1 ]; then
      cp "$f_tmp" "$target" && \
      echo "[info] results modified '$target' target" 1>&$stdout
    fi
  fi

  if [ ! -t 1 ]; then
    # i/o redirection
    for range in "${lines[@]}"; do
      sed -n ${range}'p' "$f_tmp"
    done
  fi

  echo "[info] processed $l_processed of $l_total expression$([ $l_total -ne 1 ] && echo "s"), with $l_diffs successful diff$([ $l_diffs -ne 1 ] && echo "s")" 1>&$stdout

  [ -e "$f_tmp" ] && rm "$f_tmp"
  [ -e "$f_tmp2" ] && rm "$f_tmp2"
  [ -e "$f_tmp3" ] && rm "$f_tmp3"
}

fn_test() {
  [ $# -lt 1 ] && \
    { echo "[error] not enough args" 1>&2 && return 1; }
  func="$1" && shift
  echo "[info] testing func: '$func', passing args: '$(fn_str_join "' '" "$@")'"
  $func "$@"
}

# args
option="help"
if [ $# -gt 0 ]; then
  option="debug"
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [ -n "$(echo "$arg" | sed -n '/^\(h\|help\|r\|refactor\|d\|debug\|cl\|changelog\|c\|commits\|p\|port\|test\)$/p')" ] && option="$arg" && shift
fi

case "$option" in
  "h"|"help")
    help "$@"
    ;;
  "c"|"commits")
    fn_commits "$@"
    ;;
  "cl"|"changelog")
    fn_changelog "$@"
    ;;
  "d"|"debug")
    fn_debug "$@"
    ;;
  "r"|"refactor")
    fn_refactor "$@"
    ;;
  "p"|"port")
    fn_port "$@"
    ;;
  "test")
    fn_test "$@"
    ;;
  *)
    help
    ;;
esac
