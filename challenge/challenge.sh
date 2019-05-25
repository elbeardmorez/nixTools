#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

RC_DEFAULT="$HOME/.nixTools/$SCRIPTNAME"

declare -A exts_map
exts_map["default"]="cpp|cs|py|js"

cwd="$PWD"
editor="${EDITOR:-vim}"
dump_types_default="py|js|cs"
declare -a cmd_args_editor
case $editor in
  "vim") cmd_args_editor[${#cmd_args_editor[@]}]="-p" ;;  # open files in tabs
esac

help() {
  echo -e "\nSYNTAX: $SCRIPTNAME [MODE [MODE_ARGS]]
\nwhere MODE can be:\n
  h, help  : this help information
  new [OPTIONS] TYPE CATEGORY[ CATEGORY2 [CATEGORY3 ..]] NAME
    :  create new challenge structure
    with:
      OPTIONS  :
        -ne, --no-edit  : don't invoke the editor by default
        -nss, --no-subshell  : don't drop into a subshell at the target
                               location
        -dec, --dump-edit-command  : echo editor command before exit
        -eec[=VAR], --export-edit-command[=VAR]
           : enables exporting of the derived editor command to the
             subshell var 'VAR' (default: $SCRIPTNAME)
      TYPE  : a supported challenge type
        hackerrank  : requires challenge description pdf and testcases
                      zip archive files
      CATEGORYx  : target directory name parts
      NAME  : solution name
  edit [OPTIONS] SEARCH  : search for and re-edit an existing challenge
    with:
      OPTIONS  :
        -rx, --rx-search  : switch from glob to ERE flavour searches
        and as described above:
        -nss | --no-subshell, -dec | --dump-edit-command,
        -eec[=VAR] | --export-edit-command[=VAR]
  test TYPE [OPTIONS] TEST  : run challenge tests for a language
     with:
       TYPE  : a supported challenge type
         hackerrank  : assumes 'OUTPUT_PATH' env variable
       OPTIONS  :
         -l, --language  : language to run tests with, assumes single
                           appropriately suffixed source file.
                           supported languages: c++*, c#*, python,
                           javascript (node)
                           (default: c++)
                           *compilation of source supported
       TEST  : test item (number)
  dump [LANGUAGES] TARGET  : search TARGET for files suffixed with
                             items in the delimited LANGUAGES list
                             (default: 'py|js|cs') and dump matches
                             to TARGET.LANGUAGE files
"
}

fn_exts() {
  declare target
  declare map
  target="$1" && shift
  IFSCUR="$IFS"
  IFS="|" parts=($(echo "$target" | sed 's/\.-\./|/g')); IFS="$IFSCUR"
  exts=""
  for p in "${parts[@]}"; do
    map="${exts_map["$p"]}"
    [ -n "$map" ] && exts="$map" && break
  done
  [ -z "$map" ] && exts="${exts_map["default"]}"
  echo "$exts"
}

fn_files() {
  declare target
  declare name
  declare file
  target="$1" && shift
  quote=0 && [ $# -gt 0 ] && quote=$1 && shift
  name="$(echo "$target" | sed 's/^.*\.-\.//')"
  IFSCUR="$IFS"
  IFS="|"; exts=($(fn_exts "$target")); IFS="$IFSCUR"
  lexts=${#exts[@]}
  while [ $lexts -gt 0 ]; do
    idx=$(echo "$RANDOM % ($lexts)" | bc)
    [ $DEBUG -gt 0 ] && echo "[debug] ext idx: '$idx'" 1>&2
    ext="${exts[$idx]}"
    unset 'exts['$idx']'
    IFSCUR="$IFS"
    IFS="$IFSORG"; exts=($(echo "${exts[@]}")); IFS="$IFSCUR"
    lexts=$(($lexts-1))
    file="$name.$ext"
    [ $quote -eq 1 ] && file="\"$file\""
    echo "$file"
  done
}

fn_edit_command() {
  declare target
  target="$1" && shift
  IFS=$'\n'; files=($(fn_files "$target" 1)); IFS="$IFSORG"
  for qf in "${files[@]}"; do s_files+=" $qf"; done
  echo "$editor ${cmd_args_editor[*]} ${s_files:1}"
}

# args parse
declare -a args
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [[ -z $mode && -n "$(printf "$arg" | sed -n '/^\(h\|help\|new\|edit\|test\|dump\)$/p')" ]] && mode="$arg" && shift && continue
  case "$arg" in
    *) args[${#args[@]}]="$1"
  esac
  shift
done
mode=${mode:-new}

# rc parse
if [ -e "$RC_DEFAULT" ]; then
  IFS=$'\n'; lines=($(sed -n '/^[ ]*[^#]/p' "$RC_DEFAULT")); IFS="$IFSORG"
  for kv in "${lines[@]}"; do
    IFS='|'; types=($(echo "${kv%=*}")); IFS="$IFSORG"
    maps="${kv#*=}"
    for type in "${types[@]}"; do
      exts_map["$type"]="$maps"
      [ $DEBUG -ge 1 ] && echo "[debug] added extention maps '$maps' for type '$type'"
    done
  done
fi

case "$mode" in
  "h"|"help")
    help
    exit 0
    ;;

  "new")
    edit=1
    subshell=1
    dump_edit_command=0
    export_edit_command=0
    env_var="$SCRIPTNAME"
    declare -a mode_args
    l=0
    while [ $l -lt ${#args[@]} ]; do
      kv="${args[$l]}"
      k=${kv%%=*}
      v="" && [ "x$k" != "x$kv" ] && v="${kv#*=}"
      s="$(printf " $k" | awk '{ if (/^[ ]*-+/) { gsub(/^[ ]*-+/,""); print(tolower($0)) } }')"
      case "$s" in
        "ne"|"no-edit") edit=0 ;;
        "nss"|"no-subshell") subshell=0 ;;
        "dec"|"dump-edit-command") dump_edit_command=1 ;;
        "eec"|"export-edit-command") export_edit_command=1 && [ -n "$v" ] && env_var="$v" ;;
        *) mode_args[${#mode_args[@]}]="$kv" ;;
      esac
      l=$(($l+1))
    done
    args=("${mode_args[@]}")

    type="${args[0]}" && args=("${args[@]:1}")
    case "$type" in
      "hackerrank")
        # ensure structure
        if [ "x$(basename $PWD)" != "x$type" ]; then
          [ ! -d ./"$type" ] && mkdir "$type"
          cd "$type"
        fi
        # cleanups args
        args2=()
        for s in "${args[@]}"; do
          args2[${#args2[@]}]="$(printf "$s" | tr "\- " "." | tr "A-Z" "a-z")";
        done
        args=("${args2[@]}")
        name="${args[$[$# - 1]]}"
        target="$(echo "${args[@]}" | sed 's/ /.-./g')"
        [ $DEBUG -gt 0 ] && echo "name: $name, target: $target" 1>&2
        [ ! -d "$target" ] && mkdir -p "$target"
        cd "$target" || exit 1
        IFS=$'\n'; files=($(find ./ -maxdepth 1 -iregex ".*$name.*\(pdf\|zip\)")); IFS=$IFSORG
        if [ ${#files[@]} -eq 0 ]; then
          # move files
          search="$name"
          IFS='.'; searches=($(echo "$search")); IFS="$IFSORG"
          last="${searches[0]}"
          for l in $(seq 1 1 $((${#searches[@]}-1))); do
            searches[${#searches[@]}]="$last.${searches[$l]}" && last="$last.${searches[$l]}"
          done
          for l in $(seq $((${#searches[@]}-1)) -1 0); do
            [ $DEBUG -gt 0 ] && echo "[debug] search: '${searches[$l]}'" 1>&2
            IFS=$'\n'; files=($(find $cwd -maxdepth 1 -iregex ".*${searches[$l]}.*\(pdf\|zip\)")); IFS=$IFSORG
            [ $DEBUG -gt 0 ] && echo "[debug] files#: '${#files[@]}'" 1>&2
            [ ${#files[@]} -eq 2 ] && echo "located challenge description / testcase files" && break
          done
          [ ${#files[@]} -ne 2 ] && echo "cannot locate challenge both description and testcase files" && exit 1
          for f in "${files[@]}"; do
            ext="${f##*.}"
            f2=""
            case "$ext" in
              "pdf") f2="$name.$ext" ;;
              "zip") f2="$name.testcases.$ext" ;;
              *) echo "[error] unexpected file '$f'" && exit 1
            esac
            [ ! -e "$f2" ] && mv "$f" "$f2"
          done
        fi
        [ ! -e "input" ] && unzip *zip 2>/dev/null 1>&2

        # open some appropriate files for editing
        IFS='|'; exts=($(fn_exts "$target")); IFS=IFSORG
        # ensure files
        for ext in "${exts[@]}"; do
          [ ! -f "$name.$ext" ] && touch "$name.$ext"
        done
        # editing
        s_cmd_edit="$editor ${cmd_args_editor[*]}"
        [[ ${#exts[@]} -gt 0 &&\
           ( $edit || $dump_edit_command || $export_edit_command ) ]] &&\
          s_cmd_edit="$(fn_edit_command "$target")"

        [ $edit -eq 1 ] &&\
          eval "$s_cmd_edit"
        [ $export_edit_command -eq 1 ] &&\
          eval "export $env_var='$s_cmd_edit'"
        [ $subshell -eq 1 ] &&\
          exec $(fn_shell)
        [ $dump_edit_command -eq 1 ] &&\
          echo "edit command:" 1>&2 && echo "$s_cmd_edit"
        ;;

      *)
        help && echo "[error] unsupported type '$type'" && exit 1
        ;;
    esac
    ;;

  "edit")
    declare rx
    rx=0
    subshell=1
    dump_edit_command=0
    env_var="$SCRIPTNAME"
    declare target
    declare -a targets
    declare search

    # process args
    l=0
    while [ $l -lt ${#args[@]} ]; do
      kv="${args[$l]}"
      k=${kv%%=*}
      v="" && [ "x$k" != "x$kv" ] && v="${kv#*=}"
      s="$(printf " $k" | awk '{ if (/^[ ]*-+/) { gsub(/^[ ]*-+/,""); print(tolower($0)) } }')"
      case "$s" in
        "nss"|"no-subshell") subshell=0 ;;
        "dec"|"dump-edit-command") dump_edit_command=1 ;;
        "eec"|"export-edit-command") [ -n "$v" ] && env_var="$v" ;;
        "rx"|"rx-search") rx=1 ;;
        *)
          [ -n "$search" ] && echo "[error] unsupported arg '${args[$l]}'" && exit 1
          search="${args[$l]}"
          ;;
      esac
      l=$((l+1))
    done

    # set target
    search="$(printf "$search" | tr "\- " "." | tr "A-Z" "a-z")"
    if [ $rx -eq 0 ]; then
      IFS=$'\n'; targets=($(find . -type d -iname "*$search*")); IFS="$IFSORG"
    else
      IFS=$'\n'; targets=($(find . -type d -regextype "posix-extended" -iregex "$search")); IFS="$IFSORG"
    fi
    matches=${#targets[@]}
    case $matches in
      0) echo "[info] no matches found" && exit 0 ;;
      1) target="${targets[0]}" ;;
      *) echo "[info] multiple matches found, please try a more specific search" && exit 0 ;;
    esac
    cd "$target" || exit 1
    target="$(basename "$target")"

    # set edit command
    s_cmd_edit="$(fn_edit_command "$target")"

    # execute
    if [ $subshell -eq 0 ]; then
      eval "$s_cmd_edit"
    else
      eval "export $env_var='$s_cmd_edit'"
      exec $(fn_shell)
    fi
    [ $dump_edit_command -eq 1 ] &&\
      echo "edit command:" 1>&2 && echo "$s_cmd_edit"
    ;;

  "test")
    declare language; language="c++"
    declare -A language_suffix_map
    for kv in "c++,cpp|cpp" "c#,cs|cs" "python,py|py" "javascript,node,js|js"; do
      IFS=","; ks=($(echo "${kv%|*}")); IFS="$IFSORG"
      v="${kv#*|}"
      for k in "${ks[@]}"; do
        [ $DEBUG -ge 5 ] && echo "[debug] add '$k -> $v' to languages map" 1>&2
        language_suffix_map["$k"]="$v"
      done
    done
    declare test
    declare test_file
    declare -a source_
    declare res="results"
    declare type;

    # process args
    type="${args[0]}" && args=("${args[@]:1}")
    l=0
    while [ $l -lt ${#args[@]} ]; do
      kv="${args[$l]}"
      k=${kv%%=*}
      v="" && [ "x$k" != "x$kv" ] && v="${kv#*=}"
      s="$(printf " $k" | awk '{ if (/^[ ]*-+/) { gsub(/^[ ]*-+/,""); print(tolower($0)) } }')"
      [ $DEBUG -ge 5 ] && echo "[debug] testing arg: $kv -> $s"
      case "$s" in
        "l"|"language") l=$((l + 1)) && language="${args[$l]}" ;;
        *)
          if [ -n "$(echo "${args[$l]}" | sed -n '/[0-9]\+/p')" ]; then
            test=${args[$l]}
          else
            echo "[error] unsupported arg '${args[$l]}'" && exit 1
          fi
          ;;
      esac
      l=$((l+1))
    done

    # validate args
    source_suffix="${language_suffix_map["$language"]}"
    [ -z "$source_suffix" ] && \
      help && echo "[error] unsupported language" 1>&2 && exit 1
    [ -z "$test" ] && \
      help && echo "[error] missing test arg" 1>&2 && exit 1

    case "$type" in
      "hackerrank")

        # source
        IFS=$'\n'; source_=($(find "." -maxdepth 1 -name "*$source_suffix")); IFS="$IFSORG"
        [ ${#source_[@]} -eq 0 ] && \
          echo "[error] no source file for language '$language' [$source_suffix]" 1>&2 && exit 1
        [ ${#source_[@]} -gt 1 ] && \
          echo "[error] too many source files found  for language '$language' [$source_suffix]" 1>&2 && exit 1

        # compilation
        case "$source_suffix" in
          "cpp")
            echo "[info] compiling c++ source '${source_[0]}'"
            g++ -std=c++11 -o bin "${source_[0]}" || exit 1
            ;;
          "cs")
            echo "[info] compiling c# source '${source_[0]}'"
            mcs -debug *.cs -out:bin.exe "${source_[0]}" || exit 1
            ;;
        esac

        # test
        test_file="input/input$test.txt"
        [ ! -f "$test_file" ] && \
          test_file="input/input0$test.txt"
        [ ! -f "$test_file" ] && \
          echo "[error] missing test '$test' input file" 1>&2 && exit 1

        echo "[info] running test '$test_file'"
        echo "" > "$res"
        case "$source_suffix" in
          "cpp") OUTPUT_PATH="$res" ./bin < "$test_file" > $res ;;
          "cs") OUTPUT_PATH="$res" ./bin.exe < "$test_file" > $res ;;
          "py") OUTPUT_PATH="$res" python "$source_" < "$test_file" > $res ;;
          "js") OUTPUT_PATH="$res" node "$source_" < "$test_file" > $res ;;
        esac
        ;;
      *)
        help && echo "[error] unsupported type '$type'" && exit 1
        ;;
    esac
    ;;

  "dump")
    types="$dump_types_default"
    [ ${#args[@]} -gt 1 ] && types="${args[0]}"
    target="${args[$((${#args[@]}-1))]}"
    [ ! -d "$target" ] && echo "[error] invalid target directory '$target'" && exit 1
    IFS="|/,"; types=($(echo "$types")); IFS="$IFSORG"
    for type in "${types[@]}"; do
      out="$target.$type"
      if [ -e $out ]; then
        [ $DEBUG -ge 1 ] && echo "[info] replacing existing file '$out'"
        rm "$out"
      fi
      echo "# $target | '$type' dump" >> "$out"
      IFS=$'\n'; files=($(find "$target" -type f -iname "*$type")); IFS="$IFSORG"
      for f in "${files[@]}"; do
        echo -e "\n\n/* # "$f" # */\n" >> "$out"
        cat "$f" >> "$out"
      done
    done
    ;;
esac
