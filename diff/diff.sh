#!/bin/bash

SCRIPTNAME=${0##*/}
TEST=0
DEBUG=0

mode=diff
strip=lines #files
options="-uE"
fExcludes=""

function help() {
  echo -e "
usage: $SCRIPTNAME [OPTION] dir|file dir2|file2 [IGNORE]
\nwhere OPTION is:
  dir\t\t: force directory comparison
  changed\t: list modified files
  stripfiles\t: ignore files in IGNORE list
  striplines\t: ignore lines matching IGNORE list
  whitespace\t: ignore whitespace changes
\nand IGNORE is the list of either files (OPTION stripfiles) or partial lines for regexp matching (OPTION striplines)
"
}

function dirdiff() {
  cd "$file1"; find . -name "*" -printf "%p\t%s\n" | sort > /tmp/_dirdiff1; cd "$OLDPWD"
  cd "$file2"; find . -name "*" -printf "%p\t%s\n" | sort > /tmp/_dirdiff2; cd "$OLDPWD"
  [ -f "$fExcludes" ] && $(while read line; do sed -i '/'$line'/d' /tmp/_dirdiff1; shift; done < "$fExcludes")
  [ -f "$fExcludes" ] && $(while read line; do sed -i '/'$line'/d' /tmp/_dirdiff2; shift; done < "$fExcludes")

  diff /tmp/_dirdiff1 /tmp/_dirdiff2 > /tmp/_dirdiff
  meld /tmp/_dirdiff1 /tmp/_dirdiff2 >/dev/null 2>&1 &  # more /tmp/_dirdiff
}

#args
[ $# -gt 0 ] && [ "x$1" == "xtest" ] && TEST=1 && shift
[ $# -gt 0 ] && [[ "x$1" == "x-h" || "x$1" == "x--help" ]] && help && exit
while [ "x$(echo "$1" | sed -n '/^\(dir\|changed\|strip.*\|whitespace\)$/p')" != "x" ]; do
  case "$1" in
    dir) mode="$1" && shift ;;
    changed) mode="$1" && shift ;;
    strip*) strip=$(echo "${1#strip}" | awk '{print tolower($0)}')  && shift;;
    whitespace) options+=" -w" && shift ;;
  esac
done

[ $# -lt 2 ] && help && echo "[error] two or more args required" && exit 1

file1="$1" && shift
file2="$1" && shift

if [ $# -gt 0 ]; then
  case $strip in
    "files")
      fExcludes=$(tempfile)
      while [ ! "x$1" == "x" ]; do echo "$1" >> $fExcludes; shift; done
      options+=" -X $fExcludes"
      ;;
    "lines") while [ ! "x$1" == "x" ]; do options+=" -I $1 "; shift ; done ;;
  esac
fi

#diff
if [[ -f "$file1" && -f "$file2" ]]; then
  [ $DEBUG -ge 1 ] && echo "[debug] diff $options \"$file1\" \"$file2\" | grep -ve \"^Only in\" | grep -ve \"^[Bb]inary\" | tee /tmp/_diff"
  if [ $TEST -eq 0 ]; then
    diff  $options "$file1" "$file2" | grep -ve "^Only in" | grep -ve "^[Bb]inary" | tee /tmp/_diff
    rm $fExcludes >/dev/null 2>&1 #cleanup
  fi
elif [[ -d "$file1" && -d "$file2" ]]; then
  if [ "$mode" == "dir" ]; then
    dirdiff
  else
    options+=" -r "
    [ $DEBUG -ge 1 ] && echo "[debug] diff $options  \"$file1\" \"$file2\" | grep -ve \"^Only in\" | grep -ve \"^[Bb]inary\" | tee /tmp/_diff"
    if [ $TEST -eq 0 ]; then
      diff $options  "$file1" "$file2" | grep -ve "^Only in" | grep -ve "^[Bb]inary" | tee /tmp/_diff
      rm $fExcludes >/dev/null 2>&1 #cleanup
    fi
  fi
else
  help && echo "[error] args must be a homogenous pair, either directories or files" 1>&2 && exit 1
fi

if [ "x$mode" == "xchanged" ]; then
  echo -e "\n#changes found for the following file(s)"
  cat /tmp/_diff | grep -P "^diff -" | sed 's/.*\/\(.*$\)/\1/'
fi
