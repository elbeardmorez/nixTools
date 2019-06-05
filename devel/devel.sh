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

declare -A changelog_profile_rx_file
changelog_profile_file["default"]='CHANGELOG.md'
changelog_profile_file["update"]='CHANGELOG.md'
declare -A changelog_profile_rx_id
changelog_profile_rx_id["default"]='version \([^ ]*\)'
changelog_profile_rx_id["update"]='version: \([^ ]*\)'
declare -A changelog_profile_anchor_entry
changelog_profile_anchor_entry["default"]=1
changelog_profile_anchor_entry["update"]=3

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]
\nwith OPTION:
\n  -r|--refactor  : perform code refactoring
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
\n    TARGETS  : target file(s) / dir(s) to work on
\n  -d|--debug  : call supported debugger
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
\n    support: c/c++|gdb, javascript|node inspect
\n  -cl|--changelog
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
\n    TARGET:  location of repository to query for changes
\n  -c|--commits  : process diffs into fix/mod/hack repo structure
\n    SYNTAX: $SCRIPTNAME commits [OPTIONS] [SOURCE] TARGET
\n    with OPTIONS in:
      -l|--limit [=LIMIT]  : limit number of patches to process to
                             LIMIT (default: 1)
      -f|--filter [=]FILTER  : only use commits matching the (regex)
                               expression FILTER. repeated filter args
                               are supported
      -p|--program-name  : program name (default: target directory name)
      -vcs|--version-control-system =VCS  :
        override default version control type for unknown targets
        (default: git)
      -d|--dump  : dump patch set only
\n    SOURCE  : location of repository to extract/use patch set from
              (default: '.')
\n    TARGET  : location of repository / directory to push diffs to
"
}

fn_repo_type() {
  declare vcs=""
  declare target="$1"
  [ ! -d "$target" ] && \
    echo "[error] invalid vcs root '$target'" && return 1
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

  [ $DEBUG -ge 5 ] && echo "[debug]  '$description' -> '$name'" 1>&2

  echo "$name"
}

fn_repo_search() {
  declare target; target="$1" && shift
  declare limit; limit=$1 && shift
  declare res
  declare search
  declare vcs
  vcs="$(fn_repo_type "$target")" || \
    { echo "[error] unknown vcs type for source directory '$target'" 1>&2 && return 1; }
  cd "$target" 1>/dev/null
  case "$vcs" in
    "git")
      declare -a cmd_args
      cmd_args=("--format=format:%at|%H|%s")
      [ $limit -gt 0 ] && cmd_args[${#cmd_args[@]}]="-n$limit"
      if [ $# -eq 0 ]; then
        res="$(git log "${cmd_args[@]}")"
      else
        cmd_args[${#cmd_args[@]}]="-P"
        while [ -n "$1" ]; do
          search="$1" && shift
          res="$res\n$(git log "${cmd_args}" --grep="$search")"
        done
      fi
      echo "$res"
      ;;
    *)
      echo "[user] vcs type: '$vcs' not implemented" && exit 1
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
    case "$vcs" in
      "git")
        git format-patch -k --stdout -1 "$id" > "$out"
        ;;
      *)
        echo "[user] vcs type: '$vcs' not implemented" && exit 1
        ;;
    esac
  done
  cd - 1>/dev/null || return 1
}

fn_commits() {

  declare source
  declare target
  declare limit; limit=0  # unlimited
  declare filter; filter=0
  declare -a filters
  declare program_name
  declare vcs
  declare -a commits
  declare dump; dump=0
  declare description
  declare name
  declare type
  declare res

  # process args
  declare arg
  while [ -n "$1" ]; do
    arg="$(echo "$1" | sed 's/^\ *-*//')"
    if [ ${#1} -gt ${#arg} ]; then
      case "$arg" in
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
        "p|prog-name")
          shift
          program_name="$1"
          ;;
        "vcs"|"version-control-system")
          shift
          vcs="$(echo "$1" | sed -n '/^[^-]/{s/=\?//p;}')"
          ;;
        "d"|"dump")
          dump=1
          ;;
      esac
    else
      if [ -z "$target" ]; then
        target="$1"
      elif [ -z "$source" ]; then
        source="$target"
        target="$1"
      else
        help && echo "[error] unknown arg '$1'" && return 1
      fi
    fi
    shift
  done

  # validate args
  source="${source:="."}"
  if [ ! -d "$source" ]; then
    [ -z "$source" ] && \
      echo "[error] missing '$source' directory, aborting" || \
      echo "[error] invalid source directory '$source', aborting"
    return 1
  fi
  fn_repo_type "$source" 1>/dev/null || \
    { echo "[error] unknown vcs type for source directory '$source', aborting" && return 1; }
  target="${target:="."}"
  if [ ! -d "$target" ]; then
    if [ -z "$target" ]; then
      echo "[error] missing '$target' directory, aborting" && return 1
    else
      fn_decision "[user] create target '$target'?" 1>/dev/null || return 1
      mkdir -p "$target" || return 1
    fi
  fi
  program_name="${program_name:="$target"}"
  vcs="${vcs:="$(fn_repo_type "$source")"}"

  if [ $dump -eq 0 ]; then
  # repo structure
  if [[ ! -e "$target"/fix ||
       ! -e "$target"/mod ||
       ! -e "$target"/hack ]]; then
    mkdir -p "$target"/{fix,mod,hack} 2>/dev/null
  fi
  fi

  # identify commits
  IFS=$'\n'; commits=($(fn_repo_search "$source" $limit "${filters[@]}")) || return 1; IFS="$IFSORG"
  echo "[info] ${#commits[@]} commit$([ ${#commits[@]} -ne 1 ] && echo "s") identified"
  [ ${#commits[@]} -eq 0 ] && return 1

  # process commits
  declare -a parts
  declare target_fq; target_fq="$(cd "$target" && pwd)"
  for s in "${commits[@]}"; do
    IFS="|"; parts=($(echo "$s")); IFS="$IFSORG"
    dt="${parts[0]}"
    id="${parts[1]}"
    description="${parts[2]}"
    name="$(fn_patch_name "$description")"

    if [ $dump -eq 1 ]; then
      target_fqn="$target_fq/$name"
      target_fqn_="$(fn_next_file "$target_fqn" "_" "diff")"
      [ "x$target_fqn_" != "x$target_fqn" ] && \
        echo "[info] name clash for: '$target_fqn'"
      fn_repo_pull "$source" "$id|$target_fqn_"
    else
    # get patch type
    echo "# program: $program_name | patch: '$name'"
    res="$(fn_decision "[user] set patch type (f)ix/(m)od/(h)ack/e(x)it" "f|m|h|x")"
    case "$res" in
      "f") type="fix" ;;
      "m") type="mod" ;;
      "h") type="hack" ;;
      "x") return 1 ;;
    esac

    mkdir -p "$target_fq/$type/$program_name"
    target_fqn="$target_fq/$type/$program_name/$name"
    fn_repo_pull "$source" "$id|$target_fqn"

    # append patch to repo readme
    entry="$name [git sha:$id | $([ "x$type" = "xhack" ] && echo "unsubmitted" || echo "pending")]"
    if [ -e $target_fq/$type/README ]; then
      # search for existing program entry
      if [ -z "$(sed -n '/^### '$program_name'$/p' "$target_fq/$type/README")" ]; then
        echo -e "### $program_name\n-$entry\n" >> $target_fq/$type/README
      else
        # insert entry
        sed -n -i '/^### '$program_name'$/,/^$/{/^### '$program_name'$/{h;b};/^$/{x;s/\(.*\)/\1\n-'"$entry"'\n/p;b;}; H;$!b};${x;/^### '$program_name'/{s/\(.*\)/\1\n-'"$entry"'/p;b;};x;p;b;};p' "$target_fq/$type/README"
      fi
    else
      echo -e "\n### $program_name\n-$entry\n" >> "$target_fq/$type/README"
    fi
    # append patch details to program specific readme
    comments="$(sed -n '/^Subject/,/^\-\-\-/{/^\-\-\-/{x;s/Subject[^\n]*//;s/^\n*//;p;b;};H;b;}' "$target_fq/$type/$program_name/$name")"
    echo -e "\n# $entry" >> "$target_fq/$type/$program_name/README"
    [ "x$comments" != "x" ] && echo "$comments" >> "$target_fq/$type/$program_name/README"

    # commit commands
    echo "commit: git add .; GIT_AUTHOR_DATE='$dt' GIT_COMMITTER_DATE='$dt' git commit"
    fi
  done
  [ $dump -eq 0 ] && \
  echo "# patches added to fix/mod/hack hierarchy at '$target'"
}

fn_changelog() {

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
        *) help && echo "[error] unrecognised arg '$1'" && return 1 ;;
      esac
    else
      [ -z "$target" ] && \
        target="$1" || \
        help && echo "[error] unrecognised arg '$1'" && return 1
    fi
    shift
  done

  # validate args
  [ -z "$target" ] && target="$target_default"
  [ -d "$target" ] || \
    { help && echo "[error] invalid target '$target'" && return 1; }
  vcs="$(fn_repo_type "$target")"
  [ -z "$vcs" ] && echo "[error] unsupported repository type" && return 1
  [ -z "${changelog_profiles["$profile"]}" ] && \
    { help && echo "[error] invalid profile '$profile'" && return 1; }
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
            IFS=$'\n'; commits=($(fn_repo_search "." 0)); IFS="$IFSORG"
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
              echo -e "[info] matched: [${CLR_BWN}$id${CLR_OFF}] $description\n\n'$(echo "$match" | sed 's/'"$id"'/'"$(echo -e "${CLR_HL}$id${CLR_OFF}")"'/')'\n"
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
      echo "[info] vcs type: '$vcs' not implemented" && return 1
      ;;
  esac
}

fn_debug() {

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
        *) help && echo "[error] unrecognised arg '$1'" && return 1
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
    help && echo "[error] unsupported language '$language'" && return 1

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
            if [ ${#proc[@]} -gt 0 ]; then
              echo "[info] no exact process matched '$name'. " \
                   "full command line search found ${#proc[@]} " \
                   "possibilit$([ ${#proc[@]} -eq 1 ] && echo "y" \
                                                      || echo "ies")"
              select=1  # force
            fi
          fi
        else
          pidof="$(which pidof)"
          if [ -z "$pidof" ]; then
            echo "[info] missing pgrep / pidof binaries, cannot " \
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
            l=$((l + 1))
            opts+="|$l"
            ps_="${ps%% *}"
            printf "%$((llmax - ${#l}))s[%d] %$((lp_max - ${#ps_}))s%s\n" "" $l "" "$ps_ | ${ps#* }"
          done
          opts="${opts:1}|x"
          prompt="select item # or e(${CLR_HL}x${CLR_OFF})it "
          prompt+="[${CLR_HL}1${CLR_OFF}-${CLR_HL}$l${CLR_OFF}"
          prompt+="|${CLR_HL}x${CLR_OFF}]"
          res="$(fn_decision "$(echo -e "$prompt")" "$opts" 0 0 1)"
          if [ "x$res" != "xx" ]; then
            ps="${proc[$((res - 1))]}"
            v="${ps%% *}"
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
                        "$(printf ${CLR_HL}"$info"${CLR_OFF})" \
                        $(printf "%.s-" $(seq 1 1 ${#info}))
}

fn_refactor() {

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
      echo "[error] no binary 'indent' found on this system" && return 1

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
              sed -n 'H;x;/.*)\s*\n\+\s*{.*/{s/\n/'"$(printf "${CLR_RED}%s${CLR_OFF}" "\\\n")"'\n/;p}' "$f"
              ;;
            "tabs")
              # search for tabs characters
              fn_refactor_header "> searching for 'tab characters' in file '$f'"
              sed -n 's/\t/'"$(printf ${CLR_RED})"'[ ]'"$(printf ${CLR_OFF})"'/gp' "$f"
              ;;
            "whitespace")
              # search for trailing whitespace
              fn_refactor_header "> searching for 'trailing whitespace' in file '$f'"
              IFS=$'\n'; lines=($(sed -n '/\s$/p' "$f")); IFS=$IFSORG
              for line in "${lines[@]}"; do
                echo "$line" | sed -n ':1;s/^\(.*\S\)\s\(\s*$\)/\1\'"$(printf ${CLR_RED})"'·\2/;t1;s/$/\'"$(printf ${CLR_OFF})"'/;p'
              done
              ;;
            *)
              printf "${CLR_RED}[error] missing transform '$t'${CLR_OFF}\n"
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
              printf "${CLR_RED}[error] missing transform '$t'${CLR_OFF}\n"
              ;;
          esac
          l=$((l + 1))
          [ $l -ne ${#transforms[@]} ] && printf "\n"
        done

      fi
    done

  fi
}

# args
option="help"
if [ $# -gt 0 ]; then
  option="debug"
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [ -n "$(echo "$arg" | sed -n '/^\(h\|help\|r\|refactor\|d\|debug\|cl\|changelog\|c\|commits\)$/p')" ] && option="$arg" && shift
fi

case "$option" in
  "h"|"help")
    help
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
  *)
    help
    ;;
esac
