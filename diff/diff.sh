#!/bin/bash

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

striptype_default=lines
diff_options_default="-uE"
excludes=""
option=diff

function help() {
  echo -e "
usage: $SCRIPTNAME [TYPE [TYPE_ARGS]] [OPTION [OPTION_ARGS] ..] dir|file dir2|file2
\nwhere TYPE is:
  diff     : unified diff (default)
  dir      : force directory comparison
  changed  : list modified files
\nwith supported OPTION(s):
  stripfiles FILE [FILE2 ..]     : ignore specified files
  striplines STRING [STRING2 ..] : ignore lines (regexp format)
  whitespace                     : ignore whitespace changes
"
}

function dirdiff() {
  cd "$file1"; find . -name "*" -printf "%p\t%s\n" | sort > /tmp/_dirdiff1; cd "$OLDPWD"
  cd "$file2"; find . -name "*" -printf "%p\t%s\n" | sort > /tmp/_dirdiff2; cd "$OLDPWD"
  [ -f "$excludes" ] && $(while read line; do sed -i '/'$line'/d' /tmp/_dirdiff1; shift; done < "$fExcludes")
  [ -f "$excludes" ] && $(while read line; do sed -i '/'$line'/d' /tmp/_dirdiff2; shift; done < "$fExcludes")

  diff $diff_options /tmp/_dirdiff1 /tmp/_dirdiff2 > /tmp/_dirdiff
  meld /tmp/_dirdiff1 /tmp/_dirdiff2 >/dev/null 2>&1 &  # more /tmp/_dirdiff
}

#args
while [ "x`echo "$1" | sed -n '/^\([\-]*h\(elp\)\?\|test\|dir\|changed\)$/p'`" != "x" ]; do
  case "$1" in
    "h"|"-h"|"help"|"-help"|"--help") help && exit ;;
    "test") TEST=1 ;;
    "dir"|"changed") option="$1" ;;
  esac
  shift
done
diff_options=""
while [ $# -gt 2 ]; do
  case "$1" in
    strip*)
      strip_type=`echo "${1#strip}" | awk '{print tolower($0)}'` && shift
      [ "x$strip_type" == "x" ] && strip_type=$strip_type_default
      while [ "x`echo "$1" | sed -n '/^\(whitespace\|strip.*\)$/p'`" == "x" ]; do
        excludes[${#excludes[@]}]=$1 && shift
      done
      ;;
    "whitespace") diff_options+=" -w" && shift ;;
    *) diff_options+="$1" ;;
  esac
done

[ $# -lt 2 ] && help && echo "[error] two or more args required" && exit 1

file1="$1" && shift
file2="$1" && shift

if [ $DEBUG -gt 0 ]; then
  echo "[debug] debug: $DEBUG, test: '$TEST'" 1>&2
  echo "[debug] option: '$option', strip: '$strip_type', whitespace: '$whitespace'" 1>&2
  echo "[debug] diff_options: '$diff_options', diff_options_default: '$diff_options_default'" 1>&2
  echo -e "[debug]\nfile1: '$file1'\nfile2: '$file2'" 1>&2
  if [ ${#excludes[@]} -gt 0 ]; then
    echo "[debug] excludes:" 1>&2
    for s in "${excludes[@]}"; do echo "$s" 1>&2; done
  fi
fi

case $strip_type in
  "files")
    f_excludes="$(tempfile)"
    for s in "${excludes[@]}"; do echo "$s" >> "$f_excludes"; done
    diff_options+=" -X \"$f_excludes\""
    ;;
  "lines") for s in "${excludes[@]}"; do diff_options+=" -I $s "; done ;;
esac

#diff
if [[ -f "$file1" && -f "$file2" ]]; then
  [ $DEBUG -ge 1 ] && echo "[debug] diff $diff_options $diff_options_default \"$file1\" \"$file2\" | grep -ve \"^Only in\" | grep -ve \"^[Bb]inary\" | tee /tmp/_diff"
  if [ $TEST -eq 0 ]; then
    diff $diff_options_default $diff_options $diff_options_default "$file1" "$file2" | grep -ve "^Only in" | grep -ve "^[Bb]inary" | tee /tmp/_diff
    rm $f_excludes >/dev/null 2>&1 #cleanup
  fi
elif [[ -d "$file1" && -d "$file2" ]]; then
  if [ "x$option" == "xdir" ]; then
    dirdiff
  else
    diff_options_default+=" -r "
    [ $DEBUG -ge 1 ] && echo "[debug] diff $diff_options $diff_options_default \"$file1\" \"$file2\" | grep -ve \"^Only in\" | grep -ve \"^[Bb]inary\" | tee /tmp/_diff"
    if [ $TEST -eq 0 ]; then
      diff $diff_options_default $diff_options "$file1" "$file2" | grep -ve "^Only in" | grep -ve "^[Bb]inary" | tee /tmp/_diff
      rm $f_excludes >/dev/null 2>&1 #cleanup
    fi
  fi
else
  help && echo "[error] args must be a homogenous pair, either directories or files" 1>&2 && exit 1
fi

if [ "x$option" == "xchanged" ]; then
  echo -e "\n#changes found for the following file(s)"
  cat /tmp/_diff | grep -P "^diff -" | sed 's/.*\/\(.*$\)/\1/'
fi
