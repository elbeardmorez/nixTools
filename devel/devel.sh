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

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]
\nwith OPTION:
\n  -r, --refactor  : perform code refactoring
\n    SYNTAX: $SCRIPTNAME refactor [ARGS] TARGETS
\n    ARGS:
      -f, --filter FILTER  : regexp filter to limit files to work on
                             (default: '.*')
      -d, --depth MAXDEPTH  : limit files to within MAXDEPTH target
                              hierarchy level (default: 1)
      -m, --modify  : persist transforms
      -t, --transforms TRANSFORMS  : override default refactor
                                     transforms set. TRANSFORMS is a
                                     comma delimited list of supported
                                     transforms. the 'all' transform
                                     enables all implemented transforms
                                     (default: tabs,whitespace)
          TRANFORMS:
            tabs  : replace tab characters with 2 spaces
            whitespace  : remove trailing whitespace
            braces  : inline leading control structure braces
      -xi, --external-indent [PROFILE]  : use external gnu indent
                                          binary with PROFILE
                                          (default: standard*)
                                          (support: c)
\n      *note: see README.md for PROFILE types
\n    TARGETS  : target file(s) / dir(s) to work on
\n  -d, --debug  : call supported debugger
\n    SYNTAX: $SCRIPTNAME debug [-l LANGUAGE] [-d DEBUGGER]
                                [ARGS] [-- BIN_ARGS]
\n    -l, --language LANGUAGE  : specify target language (default: c)
    -d, --debugger  : override language specific default debugger
\n    ARGS:
      gdb:  NAME, [PID]
      node inspect:  SRC, [PORT]
\n      note: the above args are overriden by default by environment
            variables of the same name, and where not, are consumed
            in a position dependent manner
\n    support: c/c++|gdb, javascript|node inspect
\n  -cl, --changelog
\n    SYNTAX: $SCRIPTNAME changelog [ARGS] [TARGET]
\n    ARGS:
      -f, --file FILE  : overwrite changelog file name
                         (default: CHANGELOG.md)
\n    TARGET:  location of repository to query for changes
\n  -c, --commits  : process diffs into fix/mod/hack repo structure
\n    SYNTAX: $SCRIPTNAME commits [ARGS]
\n    ARGS:
      [target]  : location of repository to extract/use patch set from
                  (default: '.')
      [prog]  : program name (default: target directory name)
      [vcs]  : version control type, git, svn, bzr, cvs (default: git)
      [count]  : number of patches to process (default: 1)
"
}

fn_repo_type() {
  declare target="$1"
  [ ! -d "$target" ] && \
    echo "[error] invalid vcs root '$target'" && return 1
  if [ -d "$target/.git" ]; then echo "git"
  elif [ -d "$target/.svn" ]; then echo "subversion"
  elif [ -d "$target/.bzr" ]; then echo "bazaar"
  elif [ -d "$target/.hg" ]; then echo "mercurial"
  elif [ -d "$target/.cvs" ]; then echo "cvs"
  else echo ""
  fi
}

fn_repo_search() {
  declare vcs; vcs=$1 && shift
  declare limit; limit=$1 && shift
  declare res
  declare search
  case "$vcs" in
    "git")
      declare -a cmd_args
      cmd_args=("--format=format:'%at|%H|%s'")
      [ $limit -gt 0 ] && cmd_args[${#cmd_args[@]}]="-n$limit"
      if [ $# -eq 0 ]; then
        res="$(git log "${cmd_args[@]}")"
      else
        cmd_args[${#cmd_args[@]}]="-P"
        while [ -n "$1" ]; do
          search="$1" && shift
          res="$res\n$(git log "${cmd_args}" --grep='$search')"
        done
      fi
      echo "$res"
      ;;
    *)
      echo "[user] vcs type: '$vcs' not implemented" && exit 1
      ;;
  esac
}

fn_commits() {

  target="$PWD" && [ $# -gt 0 ] && [ -e "$1" ] && target="$(cd "$1"; pwd)" && shift
  source="$target" && [ $# -gt 0 ] && [ -e "$1" ] && target="$1" && shift
  prog=$(cd "$source"; pwd) && prog="${prog##*/}" && [ $# -gt 0 ] && prog="$1" && shift
  vcs=git && [ $# -gt 0 ] && [ -n "$(echo "$(cd "$source"; pwd)" | sed -n '/\(git\|svn\|bzr\)/p')" ] && vcs="$1" && shift
  count=1 && [ $# -gt 0 ] && count=$1 && shift

  case $vcs in
    "git")
      commithash="xxx"
      if [ $count -gt 0 ]; then
        cd "$source"
        git format-patch -$count HEAD
        cd - >/dev/null
      fi
      if [[ ! -e "$target"/fix ||
           ! -e "$target"/mod ||
           ! -e "$target"/hack ]]; then
        mkdir -p commits/{fix,mod,hack}
        cd commits
      else
        cd "$target"
      fi

      mv "$source"/00*patch ./
      # process patches
      for p in 00*patch; do
        #commithash="$(cd $source; git log --format=oneline | head -n$[$count] | tail -n1 | cut -d' ' -f1; cd - 1>/dev/null)"
        commithash=$(head -n1 "$p" | cut -d' ' -f2)
        date=$(head -n3 "$p" | sed '$!d;s/Date: //')
        # name
        subject=$(sed -n '/^Subject/{N;s/\n//;s|^Subject: \[PATCH[^]]*\] \(.*\)|\1|p}' "$p")
        name="$subject"
        name=$(echo "$name" | sed 's|[ ]|.|g')
        name=$(echo "$name" | sed 's|[\/:]|_|g')
        p2="$(echo "$name" | awk '{print tolower($0)}').diff"
        [ $DEBUG -gt 0 ] && echo "moving '$p' -> '$p2'" 1>&2
        mv "$p" "$p2"
        # clean subject
        sed -i 's|^Subject: \[PATCH[^]]*\]|Subject:|' "$p2"
        # get patch type
        type=""
        echo "# prog: $prog | patch: '$p2'"
        echo -ne "set patch type [f]ix/[m]od/[h]ack/e[x]it: " 1>&2
        bRetry=1
        while [ $bRetry -gt 0 ]; do
          result=
          read -s -n 1 result
          case "$result" in
            "f"|"F") echo "$result" 1>&2; bRetry=0; type="fix" ;;
            "m"|"M") echo "$result" 1>&2; bRetry=0; type="mod" ;;
            "h"|"H") echo "$result" 1>&2; bRetry=0; type="hack" ;;
            "x"|"X") echo "$result" 1>&2; return 1 ;;
          esac
        done
        mkdir -p "$type/$prog"
        mv "$p2" "$type/$prog/"
        # append patch to repo readme
        entry="$p2 [git sha:$commithash | $([ "x$type" = "xhack" ] && echo "unsubmitted" || echo "pending")]"
        if [ -e $type/README ]; then
          # search for existing program entry
          if [ -z "$(sed -n '/^### '$prog'$/p' "$type/README")" ]; then
            echo -e "### $prog\n-$entry\n" >> $type/README
          else
            # insert entry
            sed -n -i '/^### '$prog'$/,/^$/{/^### '$prog'$/{h;b};/^$/{x;s/\(.*\)/\1\n-'"$entry"'\n/p;b;}; H;$!b};${x;/^### '$prog'/{s/\(.*\)/\1\n-'"$entry"'/p;b;};x;p;b;};p' "$type/README"
          fi
        else
          echo -e "\n### $prog\n-$entry\n" >> "$type/README"
        fi
        # append patch details to program specific readme
        comments="$(sed -n '/^Subject/,/^\-\-\-/{/^\-\-\-/{x;s/Subject[^\n]*//;s/^\n*//;p;b;};H;b;}' "$type/$prog/$p2")"
        echo -e "\n# $entry" >> "$type/$prog/README"
        [ "x$comments" != "x" ] && echo "$comments" >> "$type/$prog/README"

        # commit commands
        echo "commit: git add .; GIT_AUTHOR_DATE='$date' GIT_COMMITTER_DATE='$date' git commit"
      done

      echo "# patches added to fix/mod/hack hierarchy at '$target'"

      cd - >/dev/null
      ;;
    *)
      echo "[user] vcs type: '$vcs' not implemented" && exit 1
      ;;
  esac
}

fn_changelog() {

  declare target
  declare target_default="."
  declare vcs
  declare file; file="CHANGELOG.md"

  # process args
  declare -a args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-+/,"",$0); print(tolower($0))}')"
    if [ ${#arg} -lt ${#1} ]; then
      # process named options
      case "$arg" in
        "f"|"file") shift && file="$1" ;;
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

  cd "$target"

  declare commit
  declare commit_range;
  declare -a commits
  declare commits_count;
  declare f_tmp; f_tmp="$(fn_temp_file "$SCRIPTNAME")"
  case $vcs in
    "git")
      merge=0
      if [ -f "$file" ]; then
        # valid last logged commit?
        commit="$(head -n1 "$file" | sed -n 's/.*version \(\S*\).*/\1/p')"
        if [ -n "$commit" ]; then
          if [ -n "$(git log --format=oneline | grep "$commit")" ]; then
            [ $DEBUG -ge 1 ] && echo "[debug] last changelog commit '${commit:0:8}..' validated" 1>&2
            commit_range="$commit..HEAD"
            merge=1
          else
            echo "[info] last changelog commit '${commit:0:8}..' unrecognised, searching for merge point"
            # search
            IFS=$'\n'; commits=($(fn_repo_search "git" 0)); IFS="$IFSORG"
            declare match
            declare id
            declare description
            for c in "${commits[@]}"; do
              id="$(echo "$c" | cut -d'|' -f2)"
              match="$(grep "$id" "$file")"
              if [ -n "$match" ]; then
                description="$(echo "$c" | cut -d'|' -f3)"
                commit="$id"
                break
              fi
            done
            if [ -n "$commit" ]; then
              echo -e "[info] matched: [${CLR_BWN}$id${CLR_OFF}] $description\n\n'$(echo "$match" | sed 's/'"$id"'/'"$(echo -e "${CLR_HL}$id${CLR_OFF}")"'/')'\n"
              fn_decision "[user] merge with existing changelog at this point?" 1>/dev/null || return 1
              merge=1
              commit_range="$commit..HEAD"
            fi
          fi
        fi
        # valid first commit?
        if [ -z "$commit" ]; then
          commit="$(git log --format=oneline | tail -n 1 | cut -d' ' -f1)"
          [ -n "$(grep "$commit" "$file")" ] && merge=1
          echo "[info] fallback root commit '$commit'$([ $merge -eq 0 ] && echo " not") found in changelog"
          commit_range="$commit..HEAD"
        fi
        git log -n 1 $commit 2>/dev/null 1>&2
        [ $? -eq 0 ] && commits_count=$(git log --pretty=oneline $commit_range | wc -l)

        if [ $merge -eq 1 ]; then
          [ $DEBUG -ge 1 ] && echo "[debug] clearing any overlapping entries" 1>&2
          sed -i -n '0,/.*'$commit'\s*/{/.*'$commit'\s*/p;b;};p' "$file"
        fi
      else
        commit_range=""
        commits_count=$(git log --pretty=oneline "$commit_range" | wc -l)
        touch "$file"
      fi

      echo "[info] $commits_count commit$([ $commits_count -gt 1 ] && echo "s") to add to changelog"
      [ $commits_count -eq 0 ] && return 0

      echo "[info] $([ $merge -eq 1 ] && echo "updating" || echo "creating new") changelog"
      git log -n $commits_count --pretty=format:"%at version %H%n - %s (%an)" | awk '{if ($1 ~ /[0-9]+/) {printf strftime("%Y%b%d",$1); $1=""}; print $0}' | cat - "$file" > $f_tmp && mv $f_tmp "$file"

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

  _ARGS_="-- _ARGS_"
  case "$bin" in
    "gdb") _ARGS_="-ex 'set args _ARGS_'" ;;
  esac

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
