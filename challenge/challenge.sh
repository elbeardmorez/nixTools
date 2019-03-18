#!/bin/sh

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

declare -A type_exts
type_exts['data.structures']="cpp cs py js"
type_exts['algorithms']="cs js py"
type_exts['mathematics']="cs js py"
type_exts['python']="py"
type_exts['bash']="sh"
type_exts['c']="c"
type_exts['c++']="cpp"

cwd="$PWD"
editor="${EDITOR:-vim}"

help() {
  echo -e "\nSYNTAX: $SCRIPTNAME [OPTION [OPTIONARGS]]
\nwhere OPTION can be:\n
  h, help  : this help information
  new TYPE CATEGORY[ CATEGORY2 [CATEGORY3 ..]] NAME
    :  create new challenge structure
    with:
      TYPE :  a supported challenge type
        hackerrank  : requires challenge description pdf and testcases
                      zip archive files
      CATEGORYx  : target directory name parts
      NAME  : solution name
"
}

# options parse
declare -a args
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [[ -z $option && -n "$(echo "$arg" | sed -n '/^\(h\|help\|new\)$/p')" ]] && option="$arg" && shift && continue
  case "$arg" in
    *) args[${#args[@]}]="$1"
  esac
  shift
done
option=${option:-new}

case "$option" in
  "h"|"help")
    help
    exit 0
    ;;

  "new")
    type="${args[0]}"
    case "$type" in
      "hackerrank")
        # ensure structure
        if [ ! "x$(basename $PWD)" == "x$type" ]; then
          [ ! -d ./"$type" ] && mkdir "$type"
          cd "$type"
        fi
        # cleanups args
        args2=()
        for s in "${args[@]}"; do
          args2[${#args2[@]}]="$(echo "$s" | tr "\- " "." | tr "A-Z" "a-z")";
        done
        args=("${args2[@]}")
        name="${args[$[$# - 1]]}"
        target="$(echo "${args[@]}" | sed 's/ /.-./g')"
        [ $DEBUG -gt 0 ] && echo "name: $name, target: $target" 1>&2
        [ ! -d $target ] && mkdir -p $target
        cd $target || exit 1
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
              *) echo "unexpected file '$f'" && exit 1
            esac
            [ ! -e "$f2" ] && mv "$f" "$f2"
          done
        fi
        [ ! -e "input" ] && unzip *zip 2>/dev/null 1>&2
        # open some appropriate files for editing
        exts=()
        for p in ${args[@]}; do
          exts=(${type_exts[$p]})
          [ ${#exts[@]} -gt 0 ] && break
        done
        lexts=${#exts[@]}
        if [ $lexts -gt 0 ]; then
          files=()
          while [ $lexts -gt 0 ]; do
            idx=$(echo "$RANDOM % ($lexts)" | bc)
            [ $DEBUG -gt 0 ] && echo "[debug] ext idx: '$idx'" 1>&2
            ext=${exts[$idx]}
            unset exts[$idx]
            exts=(`echo ${exts[@]}`)
            lexts=$[$lexts - 1]
            edit=$name.$ext
            [ ! -f $edit ] && touch $edit
            files[${#files[@]}]="$edit"
          done
          $editor -p ${files[@]}
        fi
        exec bash
        ;;

      *)
        help && echo "[error] unsupported type '$type'" && exit 1
        ;;
    esac
    ;;
esac
