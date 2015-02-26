#!/bin/sh
SCRIPTNAME="${0##*/}"
TEST=0

OPTION=edit
EDITOR=vim
IFSORG="$IFS"

function help
{
  echo -e "usage '$SCRIPTNAME [option] file'"
  echo -e "\nwhere 'option':\t supported values are 'edit', 'dump', 'grep'"
  echo -e "\n\t'file':\tfile (partial) name to search for via 'search.sh'"
}
if [ $# -lt 1 ]; then
  help
  exit 1
fi

[ $# -gt 1 ] && OPTION="$1" && shift
search="$1" && shift
IFS=$'\t\n'
if [ -d "$search" ]; then
  IFS=$'\n'; docs=(`find "$search" -type f`); IFS="$IFSORG"
else
  docs=($(search_ "$search")) #interactive nested script working as long as stdout is only used for the output
fi
result=$?

cmdmv="$([ $TEST -eq 1 ] && echo "echo ")mv"

if [ $result -eq 0 ]; then
  if [ "x${docs[0]}" == "x" ]; then
    echo "[user] no files named '$search' found for $OPTION" 
  else
    for file in "${docs[@]}"; do
      if [[ -f "$file" || -h "$file" ]]; then
        case "$OPTION" in
          "strip")
            strip=${1:-"r1"}
            side=`echo "$strip" | sed -n 's/^\([lr]\?\)\([0-9]\?\)$/\1/p'`
            [ "x$side" == "x" ] && side="r" && strip="$side$strip"
            [ ${#strip} -eq 1 ] && strip="${strip}1"
            size=`echo "$strip" | sed -n 's/^\([lr]\?\)\([0-9]\+\)$/\2/p'`

            [ "x${size}" == "x" ] &&
              echo "[error] args [l|r]x" && exit 1

            if [ "x$side" == "xl" ]; then
              file2="${file:$size}"
            else
              file2="${file:0:$[${#file}-$size]}"
            fi
            echo "# stripping file: '$file', side: '$side', size: '$size', file2: '$file2'"
            [[ -e "file2" || "x${file2}" == "x" ]] &&
              echo "skipping mv '$file' -> '$file2'" && continue
            mv -i "$file" "$file2"
            ;;
          "uniq")
            fTemp=$(tempfile)
            uniq "$file" > "$fTemp"
            mv "$fTemp" "$file"
            ;;
          "edit") echo "[user] editing file: '$file'" && sleep 1 && $EDITOR "$file" ;;
          "dump"|"cat") echo "[user] dumping contents of file: '$file'" 1>&2 && sleep 1 && cat "$file" ;;
          "grep"|"find"|"search") echo "[user] searching contents of file: '$file'" && sleep 1 && grep "$1" "$file" ;;
          "trim")
            count=1 && [ $# -gt 0 ] && count=$1 && shift
            [ "x$(echo "$count" | sed -n '/^[0-9]\+$/p')" == "x" ] && echo "[error] illegal 'count' parameter argument" && exit 1
            top=0
            if [ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(top\|bottom\)/Ip')" != "x" ]; then
              [ "x$(echo "$1" | sed -n '/top/Ip')" != "x" ] && top=1 && shift
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
                    tail -n $[$(wc -l "$file" | cut -d' ' -f1) - $count] "$file" 2>/dev/null > $fTemp
                    $cmdmv "$fTemp" "$file"
                  else
                    fTemp=$(mktemp)
                    head -n $[$(wc -l "$file" | cut -d' ' -f1) - $count] "$file" 2>/dev/null > $fTemp
                    $cmdmv "$fTemp" "$file"
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
        esac
      fi
    done
  fi  
fi
