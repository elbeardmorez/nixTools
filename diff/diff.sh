#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

changed_only=0
declare -a diff_options
diff_options_default=("-uE" "--color=always")
diff_viewer=${DIFF_VIEWER:-meld}
f_excludes=""
file1=""
file2=""

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [MODE] [OPTION [ARG] ..] dir|file dir2|file2
\nwhere MODE is:
  -d, --diff      : (default) unified diff output for targets
  -ch, --changed   : list modified common files in targets (dirs
                     only)
  -fl, --filelist  : comparison of file attributes in targets (dirs
                     only)
\nand OPTION can be:
  -sf, --strip-files FILE [FILE2 ..]      : ignore specified files
  -sl, --strip-lines STRING [STRING2 ..]  : ignore lines (regexp
                                            format)
  -nw, --no-whitespace  : ignore whitespace changes
\nnote: advanced diff options can be passed to the diff binary
      directly using the '--' switch. any unrecognised options which
      follow will be treated as diff binary options
"
}

fn_clean_up() {
  [ -n $f_excludes ] && [ -e $f_excludes ] && rm $f_excludes >/dev/null 2>&1
}

fn_process() {
  mode="$1" && shift
  type="$1" && shift

  case "$mode" in
    "diff")
      [ "x$type" = "xdir" ] && diff_options[${#diff_options[@]}]="-r"

      target="$(fn_temp_file "$SCRIPTNAME")"
      touch "$target"

      [ $DEBUG -gt 0 ] && echo "[debug] diff  ${diff_options_default[@]} ${diff_options[@]} \"$file1\" \"$file2\" | grep -ve \"^Only in\" | grep -ve \"^[Bb]inary\"" | tee -a "$target"
      if [ $TEST -eq 0 ]; then
        diff ${diff_options_default[@]} ${diff_options[@]} "$file1" "$file2" | grep -ve "^Only in" | grep -ve "^[Bb]inary" >> "$target"
        if [[ "x$type" == "xdir" && $changed_only -eq 1 ]]; then
          echo -e "\n#changes found for the following file(s)"
          cat "$target" | grep -P "^diff -" | sed 's/.*\/\(.*$\)/\1/'
        else
          cat "$target"
        fi
      fi
      ;;
    "filelist")
      [ "x$type" != "xdir" ] && echo "[user] filelist mode unsupported for type '$type'" && fn_clean_up && exit 1

      # compare files in directories
      description1="$(cd "$file1" && pwd | tr '/ ' '^.')"
      description2="$(cd "$file2" && pwd | tr '/ '  '^.')"

      target1="$(fn_temp_file "$SCRIPTNAME")_dir1_$description1"
      target2="$(fn_temp_file "$SCRIPTNAME")_dir2_$description2"

      $(cd "$file1"; find . -name "*" -printf "%p\t%s\n" | sort > "$target1")
      $(cd "$file2"; find . -name "*" -printf "%p\t%s\n" | sort > "$target2")

      if [ -f "$f_excludes" ]; then
         while read line; do
           sed -i '/'$line'/d' $target1
           sed -i '/'$line'/d' $target2
         done < "$fExcludes"
      fi

      target="$(fn_temp_file "$SCRIPTNAME")"
      diff ${diff_options[@]} $target1 $target2 > "${target}_dir"

      $diff_viewer "$target1" "$target2" >/dev/null 2>&1 &
      ;;
  esac
  fn_clean_up
}

# args
option_list='diff\|filelist\|changed\|whitespace\|striplines\|stripfiles\|--'

declare -a excludes
mode=diff
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk -v "arg=$1" '{;print tolower(gensub(/^[-]+([^-]+)/,"\\1","g",arg));}')"
  case "$arg" in
    "d"|"diff") mode="diff" ;;
    "ch"|"changed") changed_only=1 ;;
    "fl"|"filelist") mode="filelist" ;;
    "sf"|"sl"|strip*)
      shift
      while [[ "x$(echo "$1" | sed -n '/^\('$option_list'\)$/p')" == "x" && $# -gt 2 ]]; do
        excludes[${#excludes[@]}]="$1" && shift
      done
      case $arg in
        "sf"|"strip-files")
          f_excludes="$(tempfile)"
          for s in "${excludes[@]}"; do echo "$s" >> "$f_excludes"; done
          diff_options[${#diff_options[@]}]="--exclude-from=\"$f_excludes\""
          ;;
        "sl"|"strip-lines")
          for s in "${excludes[@]}"; do diff_options[${#diff_options[@]}]="--ignore-matching-lines=$s"; done
          ;;
      esac
      continue
      ;;
    "nw"|"no-whitespace") diff_options[${#diff_options[@]}]="-w" ;;
    "--")
      shift
      while [[ "x$(echo "$1" | sed -n '/^\('$option_list'\)$/p')" == "x" && $# -gt 2 ]]; do
        diff_options[${#diff_options[@]}]="$1" && shift
      done
      continue
      ;;
    "test") TEST=1 ;;
    "h"|"help") help && exit ;;
    *)
      [ $# -le 2 ] && break
      help && echo "[error] unrecognised arg '$arg'" && exit 1
      ;;
  esac
  shift
done

[ $# -lt 2 ] && help && echo "[error] missing target file/dir arg(s)" && exit 1

file1="$1" && shift
file2="$1" && shift

[ ! -e "$file1" ] && help && echo "[error] invalid target '$file1'" && exit 1
[ ! -e "$file2" ] && help && echo "[error] invalid target '$file2'" && exit 1

# type
if [[ -f "$file1" && -f "$file2" ]]; then
  type="file"
elif [[ -d "$file1" && -d "$file2" ]]; then
  type="dir"
else
  help && echo "[error] file/dir args must be homogenous" && exit 1
fi

if [ $DEBUG -gt 0 ]; then
  echo "[debug] debug: $DEBUG, test: '$TEST'" 1>&2
  echo "[debug] mode: '$mode', type: '$type', whitespace: '$whitespace'" 1>&2
  echo "[debug] diff_options_default: '${diff_options_default[@]}', diff_options: '${diff_options[@]}'" 1>&2
  echo -e "[debug]\nfile1: '$file1'\nfile2: '$file2'" 1>&2
  if [ ${#excludes[@]} -gt 0 ]; then
    echo "[debug] strip excludes:" 1>&2
    for s in "${excludes[@]}"; do echo "$s" 1>&2; done
  fi
fi

fn_process "$mode" "$type"
