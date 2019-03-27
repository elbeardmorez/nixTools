#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

declare -A type_exts
type_exts["data.structures"]="cpp cs py js"
type_exts["algorithms"]="cs js py"
type_exts["mathematics"]="cs js py"
type_exts["python"]="py"
type_exts["bash"]="sh"
type_exts["c"]="c"
type_exts["c++"]="cpp"

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
  IFSTMP="$IFS"
  IFS="|" parts=($(echo "$target" | sed 's/\.-\./|/g')); IFS="$IFSTMP"
  exts=""
  for p in "${parts[@]}"; do
    map="${type_exts["$p"]}"
    [ -n "$map" ] && exts="$map" && break
  done
  echo $exts
}

fn_files() {
  declare target
  declare name
  declare file
  target="$1" && shift
  quote=0 && [ $# -gt 0 ] && quote=$1 && shift
  name="$(echo "$target" | sed 's/^.*\.-\.//')"
  IFSTMP="$IFS"
  IFS="$IFSORG"; exts=($(fn_exts "$target")); IFS="$IFSTMP"
  lexts=${#exts[@]}
  while [ $lexts -gt 0 ]; do
    idx=$(echo "$RANDOM % ($lexts)" | bc)
    [ $DEBUG -gt 0 ] && echo "[debug] ext idx: '$idx'" 1>&2
    ext="${exts[$idx]}"
    unset 'exts['$idx']'
    IFSTMP="$IFS"
    IFS="$IFSORG"; exts=($(echo "${exts[@]}")); IFS="$IFSTMP"
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
  [[ -z $mode && -n "$(printf "$arg" | sed -n '/^\(h\|help\|new\|dump\)$/p')" ]] && mode="$arg" && shift && continue
  case "$arg" in
    *) args[${#args[@]}]="$1"
  esac
  shift
done
mode=${mode:-new}

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
          IFS=$'\n'; files=($(find "$cwd" -maxdepth 1 -iregex ".*$search.*\(pdf\|zip\)")); IFS=$IFSORG
          while [ ${#files[@]} -ne 2 ]; do
            len=${#search}
            search="${search%.*}"
            [ $DEBUG -gt 0 ] && echo "[debug] search: '$search'" 1>&2
            [ ${#search} -eq $len ] && break
            IFS=$'\n'; files=($(find ../ -maxdepth 1 -iregex ".*$search.*\(pdf\|zip\)")); IFS=$IFSORG
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
        exts=($(fn_exts "$target"))
        # ensure files
        for ext in "${exts[@]}"; do
          [ ! -f "$name.$ext" ] && touch "$name.ext"
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
