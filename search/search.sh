#!/bin/sh

SCRIPTNAME="${0##*/}"
INTERACTIVE=yes
FILERESULTS=""
PATHS=(~/documents)

function help
{
  echo -e "usage '$SCRIPTNAME NAME [INTERACTIVE=yes] [FILE_RESULTS=\"\"]'"
  echo -e "\nwhere 'NAME':\t[partial] file name to search for in a list of predefined paths"
  echo -e "\n      'INTERACTIVE':\tyes/no. setting will result in no option to create the search file, and any matches will be automatically accepted"
  echo -e "\n      'FILE_RESULTS':\tfile to dump search results per line"
  echo -e "\npredefined paths are currently:"
  for path in "${PATHS[@]}"; do echo "$path"; done
}
if [ $# -lt 1 ]; then
  help
  exit 1
fi
FILESEARCH="$1"
if [ $# -gt 1 ]; then if [ "x$2" == "xno" ]; then INTERACTIVE="no"; fi; fi
if [ $# -gt 2 ]; then 
  FILERESULTS="$2"
  if [ ! -d $(dirname "$FILERESULTS") ]; then mkdir -p $(dirname "$FILERESULTS"); fi
fi

files=
found="FALSE"

if [ -f $FILESEARCH ]; then #test local
  found="TRUE"
  if [ "x${results[0]}" == "x" ]; then
    results="$FILESEARCH\t"
  else 
    results="${results[@]}""$FILESEARCH\t"
  fi
  if [ ! "x$outfile" == "x"  ]; then echo "$FILESEARCH" >> "$outfile"; fi
elif [[ ! "x$(dirname $FILESEARCH)" == "x." || "x${FILESEARCH:0:1}" == "x." ]]; then #create file
  if [ "x$INTERACTIVE" == "xyes" ]; then
    #new file. offer creation
    echo -n "[user] file '$FILESEARCH' does not exist, create it? [y/n]: " 1>&2
    retry="TRUE"
    while [ "x$retry" == "xTRUE" ]; do
      read -n 1 -s result
      case "$result" in
        "y" | "Y")
          echo $result 1>&2
          retry="FALSE"
	  found="TRUE"
	  #ensure path
          if [ ! -d "$(dirname $FILESEARCH)" ]; then mkdir -p "$(dirname $FILESEARCH)"; fi
          touch "$FILESEARCH"
          #add file
          if [ "x${results[0]}" == "x" ]; then
            results="$FILESEARCH\t"
          else 
            results="$results""$FILESEARCH\t"
          fi
          if [ ! "x$outfile" == "x"  ]; then echo "$FILESEARCH" >> "$outfile"; fi
          ;;
        "n" | "N")
          echo $result 1>&2
          retry="FALSE"
          ;;  
      esac    
    done
  fi
else #use search paths
  for path in "${PATHS[@]}"; do
    if [ ! -e "$path" ]; then
      echo "[debug] $path no longer exists!" 1>&2
    else
      files2=($(find $path -name "$FILESEARCH"))
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
      if [[ ${#files[@]} == 1 || "x$INTERACTIVE" == "xno" ]]; then
        #add
        if [ "x${results[0]}" == "x" ]; then
          results="$file\t"
        else 
          results="$results""$file\t"
        fi
        if [ ! "x$outfile" == "x"  ]; then echo "$file" >> "$outfile"; fi
      else
        result=
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
              if [ ! "x$outfile" == "x"  ]; then echo "$file" >> "$outfile"; fi
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
