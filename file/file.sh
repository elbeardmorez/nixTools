#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

TEST=0
EDITOR="${EDITOR:-vim}"
CHARSED='].[|.'
CHARGREP='].[' # '[.' is invalid syntax to sed
RENAME_OPTIONS="lower|spaces|underscores|dashes"

cmdmv="$([ $TEST -eq 1 ] && echo "echo ")mv"

help() {
  echo -e "usage '$SCRIPTNAME [option] file'
\nwhere 'option':\t supported values are 'edit', 'dump', 'grep'
\n\t'file':\tfile (partial) name to search for via 'search.sh'
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

OPTION=edit
[ $# -lt 1 ] && help && exit 1
[ $# -gt 1 ] && OPTION="$1" && shift
search="$1" && shift

if [ -d "$search" ]; then
  IFS=$'\n'; docs=($(find "$search" -type f)); IFS="$IFSORG"
else
  # interactive nested script working as long as stdout is only used for the output
  IFS=$'\t\n'; docs=($(search_ -i "$search")); IFS="$IFSORG"
fi
result=$?

[[ $result -ne 0 || -z ${docs[0]} ]] &&\
  echo "[user] no files named '$search' found for '$OPTION'" && exit 0

    for file in "${docs[@]}"; do
  ! [[ -f "$file" || -h "$file" ]] &&\
    echo "[info] skipping non-file '$file'" && continue
        case "$OPTION" in
          "strip")
            strip=${1:-"r1"}
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

          "uniq")
            fTemp=$(tempfile)
            uniq "$file" > "$fTemp"
            mv "$fTemp" "$file"
            ;;

          "edit")
            echo "[user] editing file: '$file'"
            sleep 1
            $EDITOR "$file"
            ;;

          "dump"|"cat")
            echo "[user] dumping contents of file: '$file'" 1>&2
            sleep 1
            cat "$file"
            ;;

          "grep"|"find"|"search")
            echo "[user] searching contents of file: '$file'"
            sleep 1
            grep "$1" "$file"
            ;;

          "trim")
            count=1
            [ $# -gt 0 ] && count=$1 && shift
            [ "x$(echo "$count" | sed -n '/^[0-9]\+$/p')" == "x" ] &&\
              echo "[error] illegal 'count' parameter argument" && exit 1
            top=0
            if [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/\(top\|bottom\)/Ip')" ]]; then
              [ -n "$(echo "$1" | sed -n '/top/Ip')" ] && top=1 && shift
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
                    $cmdmv "$fTemp" "$file"
                  else
                    fTemp=$(mktemp)
                    head -n $(($(wc -l "$file" | cut -d' ' -f1)-$count)) "$file" 2>/dev/null > $fTemp
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

          "rename")
            [ $# -gt 0 ] && FILTER="$1" && shift
            file="$(echo "$file" | grep -vP '(^\.{1,2}$|'"$(fnRegexp "$FILTER" grep)"'\/$)')"
            [ -z "$file" ] && continue
            [ $# -gt 0 ] && RENAME_OPTIONS="$1" && shift
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
                  if [ ! -e "$dir$file2" ]; then $cmdmv -i "$dir$file" "$dir$file2" 2>/dev/null; fi
                  ;; 
                *) echo "[info] unsupported rename option '$option'" ;;
              esac
            done
            ;;
        esac
    done
