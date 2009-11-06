#!/bin/bash

SCRIPTNAME=${0##*/}
IFSORG=$IFS

CWD="$PWD/"

RC_FILE="${RC_FILE:-"$HOME/.nixTools/$SCRIPTNAME"}"
[ -e "$RC_FILE" ] && . "$RC_FILE"

PATHMEDIA="${PATHMEDIA:-"$HOME/media/"}"

CHARPOSIX='][^$?*+'
MINSEARCH=3
VIDEXT="avi|mkv|mp4"
CMDPLAY="${CMDPLAY:-"mplayer"}"
CMDPLAY_OPTIONS="${CMDPLAY_OPTIONS:-"-tv"}"
CMDPLAY_PLAYLIST_OPTIONS="${CMDPLAY_PLAYLIST_OPTIONS:-"-p "}"
PLAYLIST="${PLAYLIST:-"/tmp/$CMDPLAY.playlist"}"

REGEX=0

OPTION="play"

function help()
{
  echo ""
  echo -e "usage: $SCRIPTNAME [search|play] 'partialfilename'\t: search for, and play media files (partially) matching the search term"
  echo ""
}

function fnDisplay()
{  
  display="${DISPLAY_:-"$DISPLAY"}"
  echo $display
}

function fnRegexp()
{
  #escape reserved characters
  sExp="$1" && shift
  sExp=$(echo "$sExp" | sed 's/\(['$CHARPOSIX']\)/\\\1/g')
  echo "$sExp"
  exit 1
}

fnSearch()
{
  # search in a set of directories
  # optionally 'iterative'ly substring search term and research until success
  # optionally 'interactive'ly search, prompting whether to return when any given path/substring returns valid results

  bVerbose=1
  [ "x$1" == "xsilent" ] && bVerbose=0 && shift
  bIterative=0
  [ "x$1" == "xiterative" ] && bIterative=1 && shift
  bInteractive=0
  [ "x$1" == "xinteractive" ] && bInteractive=1 && shift
  
  [ "x$args" == "x" ] && help && exit 1
  sSearch="$1"
  #if [ "$REGEX" -eq 0 ]; then
  #  # escape posix regex characters
  #  sSearch=${sSearch//\\//\\\\}
  #  for c in \[ \] \. \^ \$ \? \* \+; do
  #    sSearch=${sSearch//"$c"/"\\$c"}
  #   done
  #else
    sSearch="$(fnRegexp "$sSearch")"
  #fi
  IFS=$'\n'

  bContinue=1
  dirs=("$PATHMEDIA"*/)
  while [ $bContinue -eq 1 ]; do      
    for dir in "${dirs[@]}"; do
      if [ "$REGEX" -eq 1 ]; then
        # FIX: video file only filter for globs?
        #arr=($(find "$dir" -type f -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)$'))
        arr=($(find $dir -type f -iregex ".*$sSearch.*" 2>/dev/null))    
      else
        #glob match
        arr=($(find $dir -type f -iname "*$sSearch*" 2>/dev/null))    
      fi
      if [[ ${#arr[@]} -gt 0 && "x$arr" != "x" ]]; then
        bAdd=1
        if [ $bInteractive -eq 1 ]; then
          echo "[user] target: '$dir', search: '*sSearch*', found files:" 1>&2
          for f in "${arr[@]}"; do echo "  $f" 1>&2; done
          echo -n "[user] search further? [(y)es/(n)o/e(x)it]:  " 1>&2
          bRetry2=1                
          while [ $bRetry2 -eq 1 ]; do
            echo -en '\033[1D\033[K'
            read -n 1 -s result
            case "$result" in
              "x" | "X") echo -n $result; bRetry2=0; bContinue=0; echo ""; exit 0 ;;
              "n" | "N") echo -n $result; bRetry2=0; bRetry=0; bContinue=0; echo ""; break ;;
              "y" | "Y") echo -n $result; bRetry2=0; bAdd=0 ;;
              *) echo -n " " 1>&2
            esac
          done
          echo ""
        fi
        if [ $bAdd -eq 1 ]; then
          [[ ${#files[@]} -gt 0 && ! "x$files" == "x" ]] && files=("${files[@]}" "${arr[@]}") || files=("${arr[@]}")
        fi
      fi
    done

    if [[ $bIterative -eq 0 ||
      ${#sSearch} -le $MINSEARCH ||
      (${#files[@]} -gt 0 && ${files} != "x") ]]; then
      bContinue=0
    else
#      sSearch=${sSearch:0:$[${#sSearch}-1]} # too slow
      #trim back to next shortest token set, using '][)(.,:- ' delimiter
      s=$(echo "$sSearch" | sed -n 's/^\(.*\)[][)(.,: -]\+.*$/\1/p')
      [ "${#s}" -lt $MINSEARCH ] && s=${sSearch:0:$[${#sSearch}-2]}
      [ "${#s}" -lt $MINSEARCH ] && s=${sSearch:0:$[${#sSearch}-1]}
      sSearch="$s"
      echo "$sSearch" >> /tmp/search
    fi

  done

  #process list
  if [[ ${#files[@]} -gt 0 && ! "x$files" == "x" ]]; then
    printf '%s\n' "${files[@]}" | sort
  fi
  IFS=$IFSORG
}

fnPlay()
{
  sSearch="$1" && shift
  display=$(fnDisplay)

  [[ -d "$sSearch" || -f "$sSearch" ]] && DISPLAY=$display $CMDPLAY $CMDPLAY_OPTIONS "$sSearch" "$@" && exit 0
  IFS=$'\n' sMatched=($(fnSearch $([ $REGEX -eq 1 ] && echo "regex") "$sSearch" 2>/dev/null )); IFS=$IFSORG

  play=0
  cmdplay="$CMDPLAY" 
  cmdplay_options="$CMDPLAY_OPTIONS" 
  cmdplay_playlist_options="$CMDPLAY_PLAYLIST_OPTIONS" 

  echo supported file-types: $VIDEXT 1>&2
  #VIDEXT="($(echo $VIDEXT | sed 's|\||\\\||g'))"

  if [[ ${#sMatched[@]} -gt 0 && ! "x$sMatched" == "x" ]]; then
    #files to play!   
    #iterate results. prepend titles potentially requiring user interation (e.g. using discs)
    sPlaylist=
    for file in "${sMatched[@]}"; do
      prepend=0
#        title="$(echo "$file" | sed -n 's/^.*\/\([^[]*\)[. ]\+.*$/\1/p')"
      title="${file##*/}" && title="${title%[*}" && title="$(echo "$title" | sed 's/\(^\.\|\.$\)//g')" #alternative approach below
      s="$title|$file"
      #add to list
      if [ "x${sPlaylist}" == "x" ]; then
        sPlaylist=("$s")
      else
        [ $prepend -eq 1 ] && sPlaylist=("$s" "${sPlaylist[@]}") || sPlaylist=("${sPlaylist[@]}" "$s")
      fi
    done

    #iterate list and play      
    ##format title:file[:search]
    sFiles=
    for s in "${sPlaylist[@]}"; do
      title="${s%%|*}" && s=${s:$[${#title}+1]} && title="$(echo ${title##*/} | sed 's/[. ]\[.*$//I')"
      file="${s%%|*}" && s=${s:$[${#file}+1]}
      search="$s" && [ "$search" == "$file" ] && search=""
      #file type?
      if [ "x$(echo "$file" | grep -iP '^.*\.('$VIDEXT')$')" != "x" ]; then         

        #play?            
        echo -n "play '$title'? [(y)es/(n)o/(v)erbose/e(x)it]:  "
        bRetry=1                
        while [ $bRetry -eq 1 ]; do
          echo -en '\033[1D\033[K'
          read -n 1 -s result
          case "$result" in
            "y" | "Y") echo -n $result; bRetry=0 ;;
            "n" | "N") echo -n $result; bRetry=0; file="" ;;
            "v" | "V") echo -n $result; echo -en "\033[G\033[1Kplay '$file'? [(y)es/(n)o/(v)erbose/e(x)it]:  " ;;
            "x" | "X") echo -n $result; bRetry=0; echo ""; exit 0 ;;
            *) echo -n " " 1>&2
          esac
        done
        echo ""                  

        if [ "x$file" != "x" ]; then
          #add to playlist
          if [[ -e "$file" && "x$file" != "x" ]]; then
            [ "x${sFiles[@]}" == "x" ] && sFiles=("$file") || sFiles=("${sFiles[@]}" "$file")
          fi
        fi
      fi
    done
 
    #play remaining files
    if [ "x${sFiles}" != "x" ]; then
      for l in $(seq 0 1 $[${#sFiles[@]}-1]); do
        file="${sFiles[$l]}"
        #construct playlist?
        if [ "x$PLAYLIST" != "x" ]; then
          [ $l -eq 0 ] && echo "$file" > "$PLAYLIST" || echo "$file" >> "$PLAYLIST"
        else
          DISPLAY=$display $cmdplay $([ "x$cmdplay_options" != "x" ] && echo "$cmdplay_options") "$file" "$@"
        fi
      done
      [ "x$PLAYLIST" != "x" ] && DISPLAY=$display eval $cmdplay $([ "x$cmdplay_options" != x ] && echo "$cmdplay_options") $([ "x$cmdplay_playlist_options" != "x" ] && echo "${cmdplay_playlist_options}${PLAYLIST}" || echo "$PLAYLIST") "$@"
    fi
  fi

}

#args
[ $# -lt 1 ] && help && exit 1

#REGEX
[[ $# -gt 1 && "x$1" == "xregex" ]] && REGEX=1 && shift

if [ "x$(echo $1 | sed -n 's/^\('\
's\|search\|'\
'p\|play'\
'\)$/\1/p')" != "x" ]; then
  OPTION=$1
  shift
fi

#REGEX
[[ $# -gt 1 && "x$1" == "xregex" ]] && REGEX=1 && shift

args=("$@")
case $OPTION in
  "s"|"search") fnSearch "${args[@]}" ;;
  "p"|"play") fnPlay "${args[@]}" ;;
  *) help ;;
esac
