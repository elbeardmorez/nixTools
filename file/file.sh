#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"
TEST=${TEST:-0}

EDITOR="${EDITOR:-vim}"
RENAME_TRANSFORMS="lower|upper|spaces|underscores|dashes"
RENAME_TRANSFORMS_DEFAULT="lower|spaces|underscores|dashes"
CMD_MV="$([ $TEST -eq 1 ] && echo "echo ")mv"

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION [OPTION ARGS]] TARGET
\nwhere OPTION can be:\n
  -h, --help  : this help information
  -s [SIDECOUNT], --strip [SIDECOUNT]  : remove characters from target
                                         file name
    where SIDE  : either 'l' / 'r' denoting the side to remove char
                  from (default: r)
          COUNT  : the number of characters to remove from the given
                   side (default: 1)
  -u, --uniq  : remove duplicate lines from target file
  -e, --edit  : edit target file
  -d, --dump  : cat target file to stdout
  -f SEARCH, --find SEARCH  : grep target file for SEARCH string
  -t [LINES] [END], --trim [LINES] [END]  : trim target file
    where LINES  : number of lines to trim (default: 1)
          END  : either 'top' / 'bottom' denoting the end to trim from
                 (default: bottom)
  -r [FILTER] [TRANSFORMS], --rename [FILTER] [TRANSFORMS]
    : rename files using one or more supported transforms
    where FILTER  : string to match against target files. no match will
                    result in skipping
          TRANSFORMS  : delimited list comprising:
            'lower'  : convert all alpha characters to lower case
            'upper'  : convert all alpha characters to upper case
            'spaces'  : compress and replace with periods ('.')
            'underscores' : compress and replace with periods ('.')
            'dashes' : compress and replace with periods ('.')
            (default: lower|spaces|underscores|dashes)
\nand TARGET is:  either a directory of files, or a (partial) file name
                  to be located via 'search.sh'
"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
option=edit
arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
[ -n "$(echo "$arg" | sed -n '/\(h\|help\|s\|strip\|u\|uniq\|e\|edit\|d\|dump\|cat\|f\|find\|grep\|search\|t\|trim\|r\|rename\)/p')" ] && option="$arg" && shift

declare -a args
declare target
while [ -n "$1" ]; do
  [ $# -gt 1 ] && args[${#args[@]}]="$1" || target="$1"
  shift
done

# help short circuit
[[ "x$option" == "xh" || "x$option" == "xhelp" ]] && help && exit

# set targets
declare -a targets
if [ -d "$target" ]; then
  IFS=$'\n'; targets=($(find "$target" -type f)); IFS="$IFSORG"
else
  IFS=$'\n'; targets=($(search_ -i "$target")); IFS="$IFSORG"
fi

if [ ${#targets[@]} -gt 0 ]; then
  echo "[info] ${#targets[@]} target$([ ${#targets[@]} -ne 1 ] && echo "s") set for option '$option'"
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
      [ "x$side" == "x" ] && side="r" && strip="$side$strip"
      [ ${#strip} -eq 1 ] && strip="${strip}1"
      size=$(echo "$strip" | sed -n 's/^\([lr]\?\)\([0-9]\+\)$/\2/p')

      [ "x${size}" == "x" ] &&
        echo "[error] args [l|r]x" && exit 1

      if [ "x$side" == "xl" ]; then
        target2="${target:$size}"
      else
        target2="${target:0:$((${#target}-$size))}"
      fi
      echo "# stripping target: '$target', side: '$side', size: '$size', target2: '$target2'"
      [[ -e "target2" || "x${target2}" == "x" ]] &&
        echo "skipping mv '$target' -> '$target2'" && continue
      mv -i "$target" "$target2"
      ;;

   "u"|"uniq")
      tmp="$(fnTempFile $SCRIPTNAME)"
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
      [ "x$(echo "$lines" | sed -n '/^[0-9]\+$/p')" == "x" ] &&\
        echo "[error] invalid 'lines' arg '$lines'" && exit 1
      end="top"
      if [ ${#args[@]} -gt 1 ]; then
        arg="$(echo "${args[1]}" | awk '{print(tolower($0))}')"
        ! [[ "x$arg" == "xtop" || "x$arg" == "xbottom" ]] &&
          echo "[error] invalid 'end' arg '${args[1]}'" && exit 1
        end="$arg"
      fi
      echo -n "[user] trim $lines line$([ $lines -ne 1 ] && echo "s") from $end of target '$target'? [(y)es/(n)o/(c)ancel]: " 1>&2
      res="$(fnDecision "y|n|c")"
      [ "x$res" == "xc" ] && exit
      if [ "x$res" == "xy" ]; then
        tmp="$(fnTempFile $SCRIPTNAME)"
        rlines=$(($(wc -l "$target" | cut -d' ' -f1)-$lines))
        cutter="$([ "x$end" == "xtop" ] && echo "tail" || echo "head")"
        $cutter -n $rlines "$target" 2>/dev/null > "$tmp"
        $CMD_MV "$tmp" "$target"
      fi
      ;;

    "r"|"rename")
      [ ${#args[@]} -gt 0 ] && filter="${args[0]}" && shift
      target="$(echo "$target" | grep -vP '(^\.{1,2}$|'"$(fn_rx_escape "grep" "$FILTER")"'\/$)')"
      [ -z "$target" ] && continue
      transforms="$RENAME_TRANSFORMS_DEFAULT"
      if [ ${#args[@]} -gt 0 ]; then
        transforms="${args[@]}" && shift
        for transform in "${transforms[@]}"; do
          [ -z "$(echo "$transform" | sed -n '/\('"$(echo "$RENAME_TRANSFORMS" | sed 's/|/\\|/g')"'\)/p')" ] &&\
            echo "[error] unsupported rename transform '$transform'" && exit 1
        done
      fi
      IFS='|, '; transforms=($(echo $transforms)); IFS=$IFSORG
      declare target2
      dir="$(dirname "$target")/"
      target="${target##*/}"
      target2="$target"
      compress_periods=0
      for transform in "${transforms[@]}"; do
        case "$transform" in
          "lower"|"upper")
            target2="$(echo "$target2" | awk -F'\n' '{print to'$transform'($1)}')"
            ;;
          "spaces"|"underscores"|"dashes")
            compress_periods=1
            declare replace
            case "$transform" in
              "spaces") replace="[:space:]" ;;
              "underscores") repace="_" ;;
              "dashes") replace="-" ;;
            esac
            target2="$(echo "$target2" | awk -F'\n' '{gsub(/['"$replace"']+/,"."); print}')"
            ;;
        esac
      done
      [ $compress_periods -eq 1 ] &&\
        target2="$(echo "$target2" | awk -F'\n' '{gsub(/\.+/,"."); print}')"
      [ ! -e "$dir$target2" ] && $CMD_MV -i "$dir$target" "$dir$target2" 2>/dev/null
      ;;
  esac
done
