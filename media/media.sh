#!/bin/bash

SCRIPTNAME=${0##*/}
IFSORG=$IFS

CWD="$PWD/"

RC_FILE="${RC_FILE:-"$HOME/.nixTools/$SCRIPTNAME"}"
[ -e "$RC_FILE" ] && . "$RC_FILE"

PATHMEDIA="${PATHMEDIA:-"$HOME/media/"}"

CHARPOSIX='][^$?*+'
CHARSED='][|-'
CHARGREP=']['
MINSEARCH=3
VIDEXT="avi|mkv|mp4"
VIDCODECS="flv=flv,flv1|h264|x264|xvid|divx=divx,dx50,div3,div4,div5,divx\.5\.0|msmpg=msmpeg4|mpeg2"
AUDCODECS="vbs=vorbis|aac|dts|ac3|mp3=mp3,mpeg-layer-3|wma"
AUDCHANNELS="1.0ch=mono|2.0ch=2.0,2ch,2 ch,stereo|3.0ch=3.0|4.0ch=4.0|5.0ch=5.0|5.1ch=5.1"
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
  sType= && [ $# -gt 0 ] && sType="$1"
  #echo "sExp: '$sExp', sType: '$sType', CHARSED: '$CHARSED'" 1>&2
  case "$sType" in
    "grep") sExp=$(echo "$sExp" | sed 's/\(['$CHARGREP']\)/\\\1/g') ;;
    "sed") sExp=$(echo "$sExp" | sed 's/\(['$CHARSED']\)/\\\1/g') ;;
    *) sExp=$(echo "$sExp" | sed 's/\(['$CHARPOSIX']\)/\\\1/g') ;;
  esac
  #echo "#2, sExp: '$sExp'" 1>&2 
  echo "$sExp"
  exit 1
}

fnFileStreamInfo()
{
  #via ffmpeg
  sFile="$1"
  IFS=$'\n'; sInfo=($(ffmpeg -i "file:$sFile" 2>&1 | grep -iP "stream|duration")); IFS=$IFSORG
  for s in "${sInfo[@]}"; do echo "$s"; done
}

fnFileInfo()
{
  #level
  #0 raw
  #1 vid.aud.ch
  #2 length|vid.aud.ch
  #3 length|size|vid.aud.ch
  #4 length|fps|size|vid.aud.ch

  #defaults
  sLengthDefault="00:00:00.000|"
  sFpsDefault="x.xfps|"
  sSizeDefault="0x0|"
  sVideoDefault="vidxxx"
  sAudioDefault=".audxxx"
  sChannelsDefault=".x.xch"

  sLength="$sLengthDefault"
  sFps="$sFpsDefault"
  sSize="$sSizeDefault"
  sVideo="$sVideoDefault"
  sAudio="$sAudioDefault"
  sChannels="$sChannelsDefault"

  [[ $# -gt 0 && "x$(echo "$1" | sed -n '/^[0-9]\+$/p')" != "x" ]] && level=$1 && shift || level=1
  sFile="$1" && shift
  #archived?
  if [ ! -f "$sFile" ]; then
    #*IMPLEMENT
    #return requested level of info 
    sFileInfo=$(grep "$(fnRegexp "${sFile##*|}" "grep")" "${sFile%%|*}")
#    echo "${sFileInfo:${#sFile}}" && return
    [ "x${sFileInfo}" != "x" ] && echo "${sFileInfo#*|}" || echo "$sVideo$sAudio$sChannels" 
    return
  fi
  IFS=$'\n'; sInfo=($(fnFileStreamInfo $sFile)); IFS=$IFSORG
  for s in "${sInfo[@]}"; do
    case $level in
      0)
        echo "$s" 
        ;;
      *)
        if [ "x$(echo "$s" | sed -n '/^.*duration.*$/Ip')" != "x" ]; then
          if [ $level -gt 1 ]; then
            #parse duration
            sLength2=$(echo "$s" | sed -n 's/^.*duration:\s\([0-9:.]\+\),.*$/\1/Ip')
            [ ! "x$sLength2" == "x" ] && sLength="$sLength2|"          
          fi  
        elif [ "x$(echo "$s" | sed -n '/^.*video.*$/Ip')" != "x" ]; then
          if [ "x$sVideo" == "x$sVideoDefault" ]; then
            #echo "#fnFileInfo, IFS='$IFS'" 1>&2
            IFS=$'|'; aCodecs=($(echo "$VIDCODECS")); IFS=$IFSORG 
            #echo "fnFileInfo #2, IFS='$IFS'" 1>&2
            #echo "fnFileInfo, codecs: ${#aCodecs[@]}, codecs: '${aCodecs[@]}'" 1>&2
            for s2 in "${aCodecs[@]}"; do
              if [ "x$(echo "'$s2'" | sed -n '/\=/p')" == "x" ]; then
                [ "x$(echo "'$s'" | sed -n '/'"$(fnRegexp "$s2" "sed")"'/Ip')" != "x" ] && sVideo="$s2"        
              else
                #iterate and match using a list of codec descriptions
                IFS=$','; aCodecInfo=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${aCodecInfo[@]}"; do
                  [ "x$(echo """$s""" | sed -n '/'"$(fnRegexp "$s3" "sed")"'/Ip')" != "x" ] && sVideo="${s2%=*}" && break            
                done
              fi
              [ "x$sVideo" != "x$sVideoDefault" ] && break
            done
          fi
          if [[ $level -gt 2 && "x$sSize" == "x0x0|" ]]; then
            #parse size
            sSize2=$(echo "'$s'" | sed -n 's/^.*[^0-9]\([0-9]\+x[0-9]\+\).*$/\1/p')
            [ "x$sSize2" != "x" ] && sSize="$sSize2|"
          fi
          if [[ $level -gt 3 && "x$sFps" == "x$sFpsDefault" ]]; then
            #parse fps
            sFps2="$(echo "'$s'" | sed -n 's/^.*\s\+\([0-9.]\+\)\s*tbr.*$/\1/p')"
            [ "x$sFps2" == "x" ] && sFps2="$(echo "$s" | sed -n 's/^.*\s\+\([0-9.]\+\)\sfps.*$/\1/p')" 
            [ "x$sFps2" != "x" ] && sFps2="$(echo "$sFps2" | sed 's/\(\.\+0*\)$//')" 
            [ "x$sFps2" != "x" ] && sFps=$sFps2"fps|"
          fi
          #echo "fnFileInfo, sFps: '$sFps', sSize: '$sSize'" 1>&2 
        elif [ "x$(echo "'$s'" | sed -n '/^.*audio.*$/Ip')" != "x" ]; then
          if [ "x$sAudio" == "x$sAudioDefault" ]; then
            IFS=$'|'; aCodecs=($(echo "$AUDCODECS")); IFS=$IFSORG
            for s2 in "${aCodecs[@]}"; do
              if [ "x$(echo "'$s2'" | sed -n '/\=/p')" == "x" ]; then
                [ "x$(echo "'$s'" | sed -n '/'"$(fnRegexp "$s2" "sed")"'/Ip')" != "x" ] && sAudio="$s2"        
              else
                #iterate and match using a list of codec descriptions
                IFS=$','; aCodecInfo=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${aCodecInfo[@]}"; do
                  [ "x$(echo "'$s'" | sed -n '/'"$(fnRegexp "$s3" "sed")"'/Ip')" != "x" ] && sAudio="${s2%=*}" && break            
                done
              fi
              [ "x$sAudio" != "x$sAudioDefault" ] && sAudio=".$sAudio" && break
            done
          fi
          if [ "x$sChannels" == "x$sChannelsDefault" ]; then
            IFS=$'|'; aCodecs=($(echo "$AUDCHANNELS")); IFS=$IFSORG
            for s2 in "${aCodecs[@]}"; do
              if [ "x$(echo "$s2" | sed -n '/\=/p')" == "x" ]; then
                [ "x$(echo "'$s'" | sed -n '/[^0-9]'"$(fnRegexp "$s2" "sed")"'[^0-9]/Ip')" != "x" ] && sChannels="$s2"        
              else
                #iterate and match using a list of codec descriptions
                IFS=$','; aCodecInfo=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${aCodecInfo[@]}"; do
                  [ "x$(echo "'$s'" | sed -n '/[^0-9]'"$(fnRegexp "$s3" "sed")"'[^0-9]/Ip')" != "x" ] && sChannels="${s2%=*}" && break            
                done
              fi
              [ "x$sChannels" != "x$sChannelsDefault" ] && sChannels=".$sChannels" && break
            done
          fi
        fi
        ;;
    esac
  done
  [ $level -lt 2 ] && sLength=""
  [ $level -lt 3 ] && sSize=""
  [ $level -lt 2 ] && sFps="" 
  [ $level -gt 0 ] && echo "$sLength$sFps$sSize$sVideo$sAudio$sChannels"
}

fnFilesInfo()
{
  #echo "#args: $#" 1>&2
  [[ $# -gt 0 && "x$(echo "$1" | sed -n '/^[0-9]\+$/p')" != "x" ]] && level=$1 && shift || level=1
  #echo "#args: $#" 1>&2
  if [ $# -gt 1 ]; then
    sFiles=("$@")
  else
    sSearch="$1" && shift
    if [ -f "$sSearch" ]; then
      sFiles=("$sSearch")
    elif [ -d "$sSearch" ]; then
      IFS=$'\n'; sFiles=($(find "$sSearch" -type f -maxdepth 1 -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)$' | sort)); IFS=$IFSORG
      x=$? && [ $x -ne 0 ] && return $x
    else
      IFS=$'\n'; sFiles=($(fnSearch "$sSearch" "$VIDEXT")); IFS=$IFSORG
      x=$? && [ $x -ne 0 ] && return $x
    fi
  fi
  for f in "${sFiles[@]}"; do
    [ "x$(echo "$f" | grep -iP "\.($VIDEXT)$")" == "x" ] && continue
    #echo -ne "#$f$([ $level -gt 2 ] && echo '\n' || echo ' | ')"    
    if [ $level -eq 0 ]; then
      echo "#$f" && fnFileInfo $level "$f"
    else
      s=$(fnFileInfo $level "$f")
      echo -e "[$s]  \t$f"
    fi
  done
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
'p\|play\|'\
'i\|info'\
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
  "i"|"info") fnFilesInfo "${args[@]}" ;;
  *) help ;;
esac
