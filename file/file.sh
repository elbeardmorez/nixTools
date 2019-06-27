#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

EDITOR="${EDITOR:-vim}"
RENAME_FILTER="."
RENAME_TRANSFORMS="lower|upper|spaces|underscores|dashes"
RENAME_TRANSFORMS_DEFAULT="lower|spaces|underscores|dashes"
MOVE_ALIASES="$HOME/.nixTools/$SCRIPTNAME"
CMD_MV="$([ $TEST -eq 1 ] && echo "echo ")mv"
CMD_MV_ARGS=("-i")
CMD_CP="$([ $TEST -eq 1 ] && echo "echo ")cp"
CMD_CP_ARGS=("-a")

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION [OPTION ARGS]] TARGET
\nwhere OPTION can be:\n
  -h|--help  : this help information
  -s|--strip [SIDE][COUNT]  : remove characters from target file name
    where SIDE  : either 'l' / 'r' denoting the side to remove char
                  from (default: r)
          COUNT  : the number of characters to remove from the given
                   side (default: 1)
  -u|--uniq  : remove duplicate lines from target file
  -e|--edit  : edit target file
  -d|--dump  : cat target file to stdout
  -f|--find SEARCH  : grep target file for SEARCH string
  -t|--trim [LINES] [END]  : trim target file
    where LINES  : number of lines to trim (default: 1)
          END  : either 'top' / 'bottom' denoting the end to trim from
                 (default: bottom)
  -r|--rename [FILTER] [TRANSFORMS]  : rename files using one or more
                                       supported transforms
    where FILTER  : perl regular expression string for filtering out
                    (negative matching) target files. a match against
                    this string will result in skipping of a target
                    (default: '')
          TRANSFORMS  : delimited list comprising:
            'lower'  : convert all alpha characters to lower case
            'upper'  : convert all alpha characters to upper case
            'spaces'  : compress and replace with periods ('.')
            'underscores' : compress and replace with periods ('.')
            'dashes' : compress and replace with periods ('.')
            'X=Y'  : custom string replacements
            '[X]=Y'  : custom character(s) replacements
            (default: lower|spaces|underscores|dashes)
  -dp|--dupe [DEST] [SUFFIX]  : duplicate TARGET to TARGET.orig, DEST,
                                or {TARGET}{DEST} dependent upon
                                optional arguments
    where DEST  : either a path or a suffix to copy the TARGET to
          SUFFIX  : either 0 or 1, determining what DEST is used as
                    (default: 0)
  -m|--move DEST  : move TARGET to DEST - a path, or an alias which
                    can be found in the rc file
                    ('~/.nixTools/$SCRIPTNAME')
  -xs|--search-args  : pass extra search arguments to 'search_'.
                       proceeding args (optionally up to a '--')
                       are considered search args
\nand TARGET is:  either a directory of files, or a (partial) file name
                  to be located via 'search.sh'
"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
option=edit
arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
[ -n "$(echo "$arg" | sed -n '/^\(h\|help\|s\|strip\|u\|uniq\|e\|edit\|d\|dump\|cat\|f\|find\|grep\|search\|t\|trim\|r\|rename\|dp\|dupe\|m\|move\)$/p')" ] && option="$arg" && shift

declare -a search_args
search_args=("--targets" "--interactive" 1)
declare -a args
declare target
while [ $# -gt 0 ]; do
  [ $# -eq 1 ] && target="$1" && shift && break
  if [[ "x$1" == "x-xs" || "x$1" == "x--search-args" ]]; then
    shift
    while [ $# -gt 1 ]; do
      [ "x$1" = "x--" ] && break
      search_args[${#search_args[@]}]="$1"
      shift
    done
    [ $# -eq 1 ] && continue
  else
    args[${#args[@]}]="$1"
  fi
  shift
done

# help short circuit
[[ "x$option" == "xh" || "x$option" == "xhelp" ]] && help && exit

# set targets
declare -a targets
if [ -d "$target" ]; then
  case "$option" in
    "dp"|"dupe"|"m"|"move") targets=("$target") ;;
    *) IFS=$'\n'; targets=($(find "$target" -type f)); IFS="$IFSORG" ;;
  esac
else
  targets_="$(search_ "${search_args[@]}" "$target")"
  res=$? && [ $res -ne 0 ] && exit $res
  IFS=$'\n'; targets=($(echo "$targets_")); IFS="$IFSORG"
fi

[ $DEBUG -ge 5 ] && \
  { echo "[debug] targets:"; for f in "${targets[@]}"; do echo "$f"; done; }

if [ ${#targets[@]} -gt 0 ]; then
  [ $DEBUG -ge 1 ] && echo "[debug] ${#targets[@]} target$([ ${#targets[@]} -ne 1 ] && echo "s") set for option '$option'"
else
  echo "[info] no targets set for '$target'" && exit 0
fi

# process
for target in "${targets[@]}"; do
  case "$option" in
    "s"|"strip")
      strip="r1"
      [ ${#args[@]} -gt 0 ] && strip="${args[0]}"
      side=$(echo "$strip" | sed -n 's/^\([lr]\?\)\([0-9]\?\)$/\1/p')
      [ "x$side" = "x" ] && side="r" && strip="$side$strip"
      [ ${#strip} -eq 1 ] && strip="${strip}1"
      size=$(echo "$strip" | sed -n 's/^\([lr]\?\)\([0-9]\+\)$/\2/p')

      [ "x${size}" = "x" ] &&
        echo "[error] args [l|r]x" && exit 1

      if [ "x$side" = "xl" ]; then
        target2="${target:$size}"
      else
        target2="${target:0:$((${#target}-$size))}"
      fi
      echo "# stripping target: '$target', side: '$side', size: '$size', target2: '$target2'"
      [[ -e "target2" || "x${target2}" == "x" ]] &&
        echo "skipping mv '$target' -> '$target2'" && continue
      $CMD_MV ${CMD_MV_ARGS[@]} "$target" "$target2"
      ;;

   "u"|"uniq")
      tmp="$(fn_temp_file $SCRIPTNAME)"
      uniq "$target" > "$tmp"
      mv "$tmp" "$target"
      ;;

    "e"|"edit")
      echo "[user] editing target: '$target'"
      sleep 1
      $EDITOR "$target"
      ;;

    "d"|"dump"|"cat")
      echo "[user] dumping contents of target: '$target'" 1>&2
      sleep 1
      cat "$target"
      ;;

    "f"|"find"|"grep"|"search")
      echo "[user] searching contents of target: '$target'"
      sleep 1
      grep "${args[0]}" "$target"
      ;;

    "t"|"trim")
      lines=1
      [ ${args[@]} -gt 0 ] && lines=${args[0]}
      [ "x$(echo "$lines" | sed -n '/^[0-9]\+$/p')" = "x" ] &&\
        echo "[error] invalid 'lines' arg '$lines'" && exit 1
      end="top"
      if [ ${#args[@]} -gt 1 ]; then
        arg="$(echo "${args[1]}" | awk '{print(tolower($0))}')"
        ! [[ "x$arg" == "xtop" || "x$arg" == "xbottom" ]] &&
          echo "[error] invalid 'end' arg '${args[1]}'" && exit 1
        end="$arg"
      fi
      res="$(fn_decision "[user] trim $lines line$([ $lines -ne 1 ] && echo "s") from $end of target '$target'?" "ync")"
      [ "x$res" = "xc" ] && exit
      if [ "x$res" = "xy" ]; then
        tmp="$(fn_temp_file $SCRIPTNAME)"
        rlines=$(($(wc -l "$target" | cut -d' ' -f1)-$lines))
        cutter="$([ "x$end" = "xtop" ] && echo "tail" || echo "head")"
        $cutter -n $rlines "$target" 2>/dev/null > "$tmp"
        $CMD_MV "$tmp" "$target"
      fi
      ;;

    "r"|"rename")
      [ ${#args[@]} -gt 0 ] && { filter="${args[0]}" && args=("${args[@]:1}"); } || filter=$RENAME_FILTER
      target="$(echo "$target" | grep -vP '(^\.{1,2}$|'"$(fn_escape "perl" "$filter")"'\/$)')"
      [ -z "$target" ] && continue
      if [ ${#args[@]} -gt 0 ]; then
        IFS='|, '; transforms=($(echo "${args[*]}")); IFS=$IFSORG
        for transform in "${transforms[@]}"; do
          [ -z "$(echo "$transform" | sed -n '/\('"$(echo "$RENAME_TRANSFORMS" | sed 's/|/\\|/g')"'\|.\+=.*\)/p')" ] &&\
            echo "[error] unsupported rename transform '$transform'" && exit 1
        done
      else
        IFS='|, '; transforms=($(echo "$RENAME_TRANSFORMS_DEFAULT")); IFS=$IFSORG
      fi
      declare target2
      dir="$(dirname "$target")/"
      target="${target##*/}"
      target2="$target"
      compress_periods=0
      for transform in "${transforms[@]}"; do
        declare search
        declare replace
        case "$transform" in
          "lower"|"upper")
            target2="$(echo "$target2" | awk -F'\n' '{print to'$transform'($1)}')"
            ;;
          "spaces"|"underscores"|"dashes")
            compress_periods=1
            case "$transform" in
              "spaces") search="[:space:]" ;;
              "underscores") search="_" ;;
              "dashes") search="-" ;;
            esac
            replace="."
            [ $DEBUG -gt 0 ] && echo "[debug] rename transform '$search' -> '$replace'" 1>&2
            target2="$(echo "$target2" | awk -F'\n' '{gsub(/['"$search"']+/,"'$replace'"); print}')"
            ;;
         *=*)
            compress_periods=1
            search="$(fn_escape "awk" "${transform%=*}")"
            replace="$(fn_escape "awk" "${transform#*=}")"
            [ $DEBUG -gt 0 ] && echo "[debug] rename transform '$search' -> '$replace'" 1>&2
            target2="$(echo "$target2" | awk -F'\n' '{gsub(/'"$search"'+/,"'$replace'"); print}')"
            ;;
        esac
      done
      [ $compress_periods -eq 1 ] &&\
        target2="$(echo "$target2" | awk -F'\n' '{gsub(/\.+/,"."); print}')"
      [ ! -e "$dir$target2" ] && $CMD_MV ${CMD_MV_ARGS[@]} "$dir$target" "$dir$target2" 2>/dev/null
      ;;

    "dp"|"dupe")
      declare target2
      declare target_suffix

      # args
      [ ! -e "$target" ] && echo "[error] invalid target '$target'" && exit 1
      target2="$target"
      [ ${#args[@]} -gt 0 ] && target2="${args[0]}"
      target_suffix=".orig"
      [ ${#args[@]} -gt 1 ] && [ ${args[1]} -eq 1 ] && target_suffix="$target2" && target2="$target"

      # setup
      [ "x$(dirname "$target")" = "./" ] &&\
        target="$(echo "$PWD/$target" | sed 's/\/.\//\//g')"
      [ "x$(dirname "$target2")" = "./" ] &&\
        target2="$(echo "$PWD/$target2" | sed 's/\/.\//\//g')"
      [ "x$target" = "x$target2" ] && target2+="$target_suffix"
      target="$(fn_path_resolve "$target")"
      target2="$(fn_path_resolve "$target2")"

      # duplicate
      [ $DEBUG -gt 0 ] && echo "[debug] type: '$([ -d "$target" ] && echo "dir" || echo "file")', command: '$CMD_CP ${CMD_CP_ARGS[*]}', targets: '$target' -> '$target2'"
      $CMD_CP ${CMD_CP_ARGS[@]} "$target" "$target2"
      ;;

    "m"|"move")
      declare target2

      # args
      [ ! -e "$target" ] && echo "[error] invalid target '$target'" && exit 1
      [ ${#args[@]} -lt 1 ] && help && echo "[error] not enough args" && exit 1
      target2="${args[0]}"

      # match alias if available
      if [ -e "$MOVE_ALIASES" ]; then
        # ignore '#' commented lines
        IFS=$'\n'; lines=($(sed '/[ ]*#/d' "$MOVE_ALIASES")); IFS="$IFSORG"
        for kv in "${lines[@]}"; do
          k="${kv%%=*}"
          [ "x$k" = "x$target2" ] && target2="${kv#*=}" && break
        done
      fi

      # setup
      [ "x$(dirname "$target")" = "./" ] &&\
        target="$(echo "$PWD/$target" | sed 's/\/.\//\//g')"
      [ "x$(dirname "$target2")" = "./" ] &&\
        target2="$(echo "$PWD/$target2" | sed 's/\/.\//\//g')"
      target="$(fn_path_resolve "$target")"
      target2="$(fn_path_resolve "$target2")"

      # move
      [ $DEBUG -gt 0 ] && echo "[debug] type: '$([ -d "$target" ] && echo "dir" || echo "file")', command: '$CMD_MV ${CMD_MV_ARGS[*]}', targets: '$target' -> '$target2'"
      $CMD_MV ${CMD_MV_ARGS[@]} "$target" "$target2"
      ;;
  esac
done
