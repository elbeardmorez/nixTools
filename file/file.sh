#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

TEST=0
EDITOR="${EDITOR:-vim}"
CHARSED='].[|.'
CHARGREP='].[' # '[.' is invalid syntax to sed
RENAME_OPTIONS="lower|spaces|underscores|dashes"
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
  -r [TRANSFORMS], --rename [TRANSFORMS]  : rename files using one or
                                            more supported transforms
    where TRANSFORMS  : delimited list comprising 'lower', 'upper',
                        'spaces', 'underscores', 'dashes'
\nand TARGET is:  a (partial) file name to locate via 'search.sh'
"
}

function fnRegexp()
{
  #escape reserved characters
  sExp="$1" && shift
  sType= && [ $# -gt 0 ] && sType="$1"
  case "$sType" in
    "grep") sExp=$(echo "$sExp" | sed 's/\(['$CHARGREP']\)/\\\1/g') ;;
    *) sExp=$(echo "$sExp" | sed 's/\(['$CHARSED']\)/\\\1/g') ;;
  esac
  echo "$sExp"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
option=edit
arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
[ -n "$(echo "$arg" | sed -n '/\(h\|help\|s\|strip\|u\|uniq\|e\|edit\|d\|dump\|cat\|f\|find\|grep\|search\|t\|trim\|r\|rename\)/p')" ] && option="$arg" && shift

declare -a args
declare search
while [ -n "$1" ]; do
  [ $# -gt 1 ] && args[${#args[@]}]="$1" || search="$1"
  shift
done

# locate TARGET, search
if [ -d "$search" ]; then
  IFS=$'\n'; files=($(find "$search" -type f)); IFS="$IFSORG"
else
  # interactive nested script working as long as stdout is only used for the output
  IFS=$'\t\n'; files=($(search_ -i "$search")); IFS="$IFSORG"
fi
res=$?

[[ $res -ne 0 || -z ${files[0]} ]] &&\
  echo "[user] no files named '$search' found for '$option'" && exit 0

# process
for file in "${files[@]}"; do
  ! [[ -f "$file" || -h "$file" ]] &&\
    echo "[info] skipping non-file '$file'" && continue
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
        file2="${file:$size}"
      else
        file2="${file:0:$((${#file}-$size))}"
      fi
      echo "# stripping file: '$file', side: '$side', size: '$size', file2: '$file2'"
      [[ -e "file2" || "x${file2}" == "x" ]] &&
        echo "skipping mv '$file' -> '$file2'" && continue
      mv -i "$file" "$file2"
      ;;

   "u"|"uniq")
      fTemp=$(tempfile)
      uniq "$file" > "$fTemp"
      mv "$fTemp" "$file"
      ;;

    "e"|"edit")
      echo "[user] editing file: '$file'"
      sleep 1
      $EDITOR "$file"
      ;;

    "d"|"dump"|"cat")
      echo "[user] dumping contents of file: '$file'" 1>&2
      sleep 1
      cat "$file"
      ;;

    "f"|"find"|"grep"|"search")
      echo "[user] searching contents of file: '$file'"
      sleep 1
      grep "${args[0]}" "$file"
      ;;

    "t"|"trim")
      count=1
      [ ${args[@]} -gt 0 ] && count=${args[0]}
      [ "x$(echo "$count" | sed -n '/^[0-9]\+$/p')" == "x" ] &&\
        echo "[error] illegal 'count' parameter argument" && exit 1
      top=0
      if [[ ${#args[@]} -gt 1 && -n "$(echo "${args[1]}" | sed -n '/\(top\|bottom\)/Ip')" ]]; then
        [ -n "$(echo "${args[1]}" | sed -n '/top/Ip')" ] && top=1
      fi
      echo -n "[user] trim $count lines from $([ $top -eq 1 ] && echo "top" || echo "bottom") of file '$file'? [(y)es/(n)o/e(x)it]:  " 1>&2
      bRetry=1
      while [ $bRetry -eq 1 ]; do
        echo -en '\033[1D\033[K'
        read -n 1 -s result
        case "$result" in
          "y"|"Y")
            echo $result
            if [ $top -eq 1 ]; then
              fTemp=$(mktemp)
              tail -n $(($(wc -l "$file" | cut -d' ' -f1)-$count)) "$file" 2>/dev/null > $fTemp
              $CMD_MV "$fTemp" "$file"
            else
              fTemp=$(mktemp)
              head -n $(($(wc -l "$file" | cut -d' ' -f1)-$count)) "$file" 2>/dev/null > $fTemp
              $CMD_MV "$fTemp" "$file"
            fi
            bRetry=0
            ;;
          "n"|"N")
            echo $result
            bRetry=0
            ;;
          "x"|"X")
            echo $result
            exit 0
            ;;
          *) echo -n " " 1>&2 ;;
        esac
      done
      ;;

    "r"|"rename")
      [ ${#args[@]} -gt 0 ] && FILTER="${args[0]}" && shift
      file="$(echo "$file" | grep -vP '(^\.{1,2}$|'"$(fnRegexp "$FILTER" grep)"'\/$)')"
      [ -z "$file" ] && continue
      [ ${#args[@]} -gt 0 ] && RENAME_OPTIONS="${args[0]}" && shift
      IFS='|, '; options=($RENAME_OPTIONS); IFS=$IFSORG
      for option in "${options[@]}"; do
        case "$option" in
          "lower"|"upper"|"spaces"|"underscores"|"dashes")
            dir="$(dirname "$file")/"
            file=${file##*/}
            case "$option" in
              "lower"|"upper") file2="$(echo $file | awk -F'\n' '{print to'$option'($1)}')" ;;
              "spaces") file2="$(echo $file | awk -F'\n' '{gsub("[[:space:]]","."); print}')" ;;
              "underscores") file2="$(echo $file | awk -F'\n' '{gsub("_","."); print}')" ;;
              "dashes") file2="$(echo $file | awk -F'\n' '{gsub("-","."); print}')" ;;
            esac
            if [ ! -e "$dir$file2" ]; then $CMD_MV -i "$dir$file" "$dir$file2" 2>/dev/null; fi
            ;;

          *)
            echo "[info] unsupported rename option '$option'"
            ;;
        esac
      done
      ;;
  esac
done
