#!/bin/sh

SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

PATHS=(~/documents)
FILE_RESULTS=""
SEARCH_TARGETS="$HOME/.search"
SEARCH=""
search_targets=0
interactive=0

help() {
  echo -e "SYNTAX '$SCRIPTNAME [OPTIONS] SEARCH
\nwhere 'OPTIONS' can be\n
  -h, --help  : this help information
  -i, --interactive  : enable verification prompt for each match
                       (default: off / auto-accept)
  -t, --target TARGETS  : file containing search targets, one per line
                          (default: ~/.search)
  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line
\nand 'SEARCH' is  : a (partial) file name to search for in the list of
                     predefined search paths*
\n*predefined paths are currently: $(for path in "${PATHS[@]}"; do echo -e "\n$path"; done)
"
}

# parse options
[ $# -lt 1 ] && help && echo "[error] not enough args" && exit 1
while [ -n "$1" ]; do
  arg="$(echo "$1" | sed 's/[ ]*-*//g')"
  case "$arg" in
    "h"|"help") help && exit ;;
    "i"|"interactive") interactive=1 ;;
    "t") search_targets=1 ;;
    "target") search_targets=1 && shift && SEARCH_TARGETS="$1" ;;
    "r"|"results") shift && FILE_RESULTS="$1" ;;
    *) [ -n "$SEARCH" ] && help && echo "[error] unknown arg '$arg'"; SEARCH="$1" ;;
  esac
  shift
done

# option verification
if [ -n "$FILE_RESULTS" ]; then
  [ -d "$(dirname "$FILE_RESULTS")" ] || mkdir -p "$(dirname "$FILE_RESULTS")"
fi
if [ $search_targets -eq 1 ]; then
  [ ! -f "$SEARCH_TARGETS" ] && echo "[error] invalid search targets file '$SEARCH_TARGETS'" && exit 1
fi

declare files
found="FALSE"

if [ -f $SEARCH ]; then
  # prioritise local files
  found="TRUE"
  if [ "x${results[0]}" == "x" ]; then
    results="$SEARCH\t"
  else
    results="${results[@]}""$SEARCH\t"
  fi
  [ -n "$FILE_RESULTS" ] && echo "$SEARCH" >> "$FILE_RESULTS"
elif [[ ! "x$(dirname $SEARCH)" == "x." || "x${SEARCH:0:1}" == "x." ]]; then
  # create file
  if [ $interactive -eq 1 ]; then
    # new file. offer creation
    echo -n "[user] file '$SEARCH' does not exist, create it? [y/n]: " 1>&2
    retry="TRUE"
    while [ "x$retry" == "xTRUE" ]; do
      read -n 1 -s result
      case "$result" in
        "y" | "Y")
          echo $result 1>&2
          retry="FALSE"
          found="TRUE"
          #ensure path
          if [ ! -d "$(dirname $SEARCH)" ]; then mkdir -p "$(dirname $SEARCH)"; fi
          touch "$SEARCH"
          #add file
          if [ "x${results[0]}" == "x" ]; then
            results="$SEARCH\t"
          else
            results="$results""$SEARCH\t"
          fi
          if [ ! "x$FILE_RESULTS" == "x"  ]; then echo "$SEARCH" >> "$FILE_RESULTS"; fi
          ;;
        "n" | "N")
          echo $result 1>&2
          retry="FALSE"
          ;;
      esac
    done
  fi
else
  # use search paths
  paths="${PATHS[@]}"
  if [ $search_targets -eq 1 ]; then
    IFS=$'\n'; paths=($(cat "$SEARCH_TARGETS")); IFS="$IFSORG"
  fi
  for path in "${paths[@]}"; do
    path="$(eval "echo $path")"  # resolve target
    if [ ! -e "$path" ]; then
      echo "[info] path '$path' no longer exists!" 1>&2
    else
      files2=($(find $path -name "$SEARCH"))
      for file in "${files2[@]}"; do
        if [[ -f "$file" || -h "$file" ]]; then
          if [ "x${files[0]}" == "x" ]; then
            files=("$file")
          else
            files=("${files[@]}" "$file")
          fi
        fi
      done
    fi
  done

  results=""
  if [ ${#files[0]} -gt 0 ]; then
    found="TRUE"
    cancel="FALSE"
    for file in "${files[@]}"; do
      if [[ ${#files[@]} == 1 || $interactive -eq 0 ]]; then
        # add
        if [ "x${results[0]}" == "x" ]; then
          results="$file\t"
        else
          results="$results""$file\t"
        fi
        if [ ! "x$FILE_RESULTS" == "x"  ]; then echo "$file" >> "$FILE_RESULTS"; fi
      else
        result=""
        echo -n "[user] search match. use file: '$file'? [y/n/c] " 1>&2
        retry="TRUE"
        while [ "x$retry" == "xTRUE" ]; do
          read -n 1 -s result
          case "$result" in
            "y" | "Y")
              echo $result 1>&2
              retry="FALSE"
              if [ "x${results[0]}" == "x" ]; then
                results="$file\t"
              else
                results="$results""$file\t"
              fi
              if [ ! "x$FILE_RESULTS" == "x"  ]; then echo "$file" >> "$FILE_RESULTS"; fi
              ;;
            "n" | "N")
              echo $result 1>&2
              retry="FALSE"
              ;;
            "c" | "C")
              echo $result 1>&2
              retry="FALSE"
              cancel="TRUE"
              ;;
          esac
        done
      fi
      if [ "x$cancel" == "xTRUE" ]; then break; fi
    done
  fi
fi

if [[ "x$found" == "xFALSE" || "x$results" == "x" ]]; then
  echo ""
else
  echo -e ${results:0:$[${#results}-2]}
fi
