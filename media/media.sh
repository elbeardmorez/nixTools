#!/bin/bash

SCRIPTNAME=${0##*/}
IFSORG=$IFS

CWD="$PWD/"

RC_FILE="${RC_FILE:-"$HOME/.nixTools/$SCRIPTNAME"}"
[ -e "$RC_FILE" ] && . "$RC_FILE"

ROOTDISK="${ROOTDISK:-"/media/"}"
ROOTISO="${ROOTISO:-"/media/iso/"}"
PATHMEDIA="${PATHMEDIA:-"$HOME/media/"}"
PATHARCHIVELISTS="${PATHARCHIVELISTS:-"${PATHMEDIA}/archives/"}"

CHARPOSIX='][^$?*+'
CHARSED='][|-'
CHARGREP=']['
MINSEARCH=3
VIDEXT="avi|mpg|mpeg|mkv|mp4"
VIDCODECS="flv=flv,flv1|h264|x264|xvid|divx=divx,dx50,div3,div4,div5,divx\.5\.0|msmpg=msmpeg4|mpeg2"
AUDCODECS="vbs=vorbis|aac|dts|ac3|mp3=mp3,mpeg-layer-3|wma"
AUDCHANNELS="1.0ch=mono|2.0ch=2.0,2ch,2 ch,stereo|3.0ch=3.0|4.0ch=4.0|5.0ch=5.0|5.1ch=5.1"
CMDPLAY="${CMDPLAY:-"mplayer"}"
CMDPLAY_OPTIONS="${CMDPLAY_OPTIONS:-"-tv"}"
CMDPLAY_PLAYLIST_OPTIONS="${CMDPLAY_PLAYLIST_OPTIONS:-"-p "}"
CMDINFOMPLAYER="${CMDINFOMPLAYER:-"mplayer -identify -frames 0 -vc null -vo null -ao null"}"
PLAYLIST="${PLAYLIST:-"/tmp/$CMDPLAY.playlist"}"
LOG="${LOG:-"/var/log/$SCRIPTNAME"}"

REGEX=0

OPTION="play"

function help()
{
  echo ""
  echo -e "usage: $SCRIPTNAME [OPTION] TARGET"
  echo ""
  echo "with OPTION:"
  echo ""
  echo -e "\tplay  : play media file(s)"
  echo -e "\tsearch  : search for file(s) only"
  echo -e "\tinfo  : output formatted information on file(s)"
  echo -e "\tarchive  : recursively search a directory and list valid media files with their info, writing all output to a file"
  echo ""
  echo "with TARGET:  a target file / directory or a partial file name to search for"
  echo ""
}

function fnLog()
{
  [ $DEBUG -ge 2 ] && echo "[debug fnLog]" 1>&2

  echo "$@" | tee $LOG 1>&2
}

function fnDisplay()
{  
  display="${DISPLAY_:-"$DISPLAY"}"
  echo $display
}

function fnDriveStatus()
{
  [ $DEBUG -ge 1 ] && echo "[debug fnDriveStatus]" 1>&2

  [ "x$(cdrecord -V --inq dev=/dev/dvd 2>&1 | grep "medium not present")" == "x" ] && echo 1 || echo -1
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

function fnPositionTimeValid()
{
  pos="$1"
  if [ "x$(echo "$pos" | sed -n 's|^\([+-/*]\{,1\}\s*[0-9:]*[0-9]\{2\}:[0-9]\{2\}[:,.]\{1\}[0-9]\{1,\}\)$|\1|p')" == "x" ]; then
    echo "illegal position format. require '00:00:00[.,:]0[00...]'" 1>&2
    echo 0
  else
    echo 1
  fi
}

function fnPositionNumericValid()
{
  num="$1"
  [ "x$(echo "$num" | sed -n '/.*[.,:]\{1\}[0-9]\+/p')" == "x" ] && num="$num.0"
  if [ "x$(echo "$num" | sed -n 's|^\([+-/*]\{,1\}\s*[0-9]\+[:,.]\{1\}[0-9]\{1,\}\)$|\1|p')" == "x" ]; then
    echo "illegal number format. require '0[.,:]0[00...]'" 1>&2
    echo 0
  else
    echo 1
  fi
}

function fnPositionNumericToTime()
{
  #convert float to positon string  

  sPrefix="$(echo "$1" | sed -n 's/^\([^0-9]\+\).*$/\1/p')"
  lNum="${1:${#sPrefix}}"
  shift
  [ $(fnPositionNumericValid "$lNum") -eq 0 ] && exit 1
  lToken="-1" && [ $# -gt 0 ] && lToken=$1 && shift
  sDelimMilliseconds="." && [ $# -gt 0 ] && sDelimMilliseconds="$1" && shift
  #IFS='.,:' && sTokens=($(echo "$sPos")) && IFS=$IFSORG
  #lTokens=${lTokens:-${#sTokens[@]}}
  ##force emtpy tokens if required
  #if [ $lTokens -ne ${#sTokens[@]} ]; then
  #  for l in $(seq ${#sTokens[@]} 1 $lTokens); do sTokens[$[$l-1]]="00"; done
  #fi
  IFS='.,:' && sTokens=($(echo "$lNum")) && IFS=$IFSORG

  sTotal=$(printf "%.3f" "0.${sTokens[1]}" | cut -d'.' -f2) #milliseconds
  lCarry=${sTokens[0]} #the rest!
  local l
  while [[ `echo "$lCarry > 0" | bc` -eq 1 || $l -lt $lToken || $l -le 1 ]]; do
    case $l in
      1) #seconds
        lCarry2=`echo "scale=0;($lCarry)/60" | bc`
        sTotal="$(printf "%02d" `echo "scale=0;($lCarry-($lCarry2*60))" | bc`).$sTotal"
        lCarry=$lCarry2
        ;;
      2) #minutes
        lCarry2=`echo "scale=0;($lCarry)/60" | bc`
        sTotal="$(printf "%02d" `echo "scale=0;($lCarry-($lCarry2*60))" | bc`):$sTotal"
        lCarry=$lCarry2
        ;;
      3) #hours
        lCarry2=`echo "scale=0;($lCarry)/24" | bc`
        sTotal="$(printf "%02d" `echo "scale=0;($lCarry-($lCarry2*24))" | bc`):$sTotal"
        lCarry=$lCarry2
        ;;
      4) #days
        sTotal="$lCarry:$sTotal"
        lCarry=0
        ;;
    esac
    l=$[$l+1]
  done
  echo "$sPrefix$(echo "$sTotal" | sed 's/\./'$sDelimMilliseconds'/')"
}

function fnPositionTimeToNumeric()
{
  #convert sPositon string to float  

  sPrefix="$(echo "$1" | sed -n 's/^\([^0-9]\+\).*$/\1/p')"
  sPos="${1:${#sPrefix}}"
  [ $(fnPositionTimeValid "$sPos") -eq 0 ] && exit 1
  IFS='.,:' && sTokens=($(echo "$sPos")) && IFS=$IFSORG
  lTotal=0
  lScale=3
  local l
  for l in $(seq 0 1 $[${#sTokens[@]}-1]); do
    sToken=${sTokens[$[${#sTokens[@]}-$l-1]]}
#    echo "$sToken"
    case $l in
      0) lScale=${#sToken}; lTotal=`echo "scale=$lScale;$sToken/(10^${#sToken})" | bc` ;; #milliseconds
      1) lTotal=`echo "scale=$lScale;$lTotal+$sToken" | bc` ;; #seconds
      2) lTotal=`echo "scale=$lScale;$lTotal+($sToken*60)" | bc` ;; #minutes
      3) lTotal=`echo "scale=$lScale;$lTotal+($sToken*3600)" | bc` ;; #hours
      4) lTotal=`echo "scale=$lScale;$lTotal+($sToken*24*3600)" | bc`;; #days
    esac
  done
  echo $sPrefix$lTotal
}

function fnPositionAdd()
{
  #iterate through : delimited array, adding $2 $1 ..carrying an extra 1 iff length of result
  #is greater than the length of either ot the original numbers

  base="$1"
  bump="$2"
  [[ $(fnPositionTimeValid "$base") -eq 0 || $(fnPositionTimeValid "$bump") -eq 0 ]] && echo "$base" &&  return 1

  IFS=$'\:\,\.'
  aBase=($base)
  aBump=($bump)
  IFS=$IFSORG
  sFinal=""
  lCarry=0
  l=${#aBase[@]}
  while [ $l -gt 0 ]; do
    lBase=${aBase[$[$l-1]]}
    lBump=${aBump[$[$l-1]]}
    lRes=$((10#$lBase+10#$lBump+10#$lCarry))
    if [ ${#lBase} -eq 2 ]; then
      sToken=$[10#$lRes%60]
      lCarry=$[$[10#$lRes-10#$lRes%60]/60]
    else
      if [ ${#lRes} -gt ${#lBase} ]; then
        sToken=${lRes:1:${#lBase}}
        lCarry=1
      else
        sToken=$lRes
        lCarry=0
      fi
    fi
    #re-pad token
    if [ ${#sToken} -lt ${#lBase} ]; then
      ll=${#sToken}
      while [ ${#sToken} -lt ${#lBase} ]; do
        sToken="0"$sToken
      done
    fi 
    if [ "x$sFinal" == "x" ]; then
      sFinal=$sToken
    else
      sFinal="$sToken${base:$[${#base[0]}-${#sFinal[0]}-1]:1}$sFinal"
    fi
    l=$[$l-1]
  done
  echo "$sFinal"
}

fnFileStreamInfo()
{
  #via ffmpeg
  sFile="$1"
  IFS=$'\n'; sInfo=($(ffmpeg -i "file:$sFile" 2>&1 | grep -iP "stream|duration")); IFS=$IFSORG
  #via mplayer
  #ID_VCD_TRACK_1_MSF=00:16:63.0
  if [ ${#sInfo[@]} -eq 0 ]; then
    IFS=$'\n'; sInfo=($($CMDINFOMPLAYER "$sFile" 2>/dev/null | sed -n '/^\(VIDEO\|AUDIO\).*$/p')); IFS=$IFSORG
    IFS=$'\n'; sTracks=($($CMDINFOMPLAYER "$sFile" 2>/dev/null | sed -n 's/^ID_VCD_TRACK_\([0-9]\)_MSF=\([0-9:]*\)$/\1|\2/p')); IFS=$IFSORG  
    if [ ${#sTracks[@]} -gt 0 ]; then
      sTrackTime2=
      for s in "${sTracks[@]}"; do
        sTrackTime2=$(fnPositionTimeToNumeric "${s##*|}")
        if [[ "x$sTrack" == "x" || $(math_ "\$gt($sTrackTime2, $sTrackTime)") -eq 1 ]]; then
          sTrack="${s%%|*}"
          sTrackTime="$sTrackTime2"
        fi
      done
      s="duration: $(fnPositionNumericToTime $sTrackTime),"
      [ ${#sInfo[@]} -eq 0 ] && sInfo=("$s") || sInfo=("${sInfo[@]}" "$s")
    fi
  fi
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
  [[ "x$sAudio" == "x$sAudioDefault" && "x$sVideo" == "xmpeg2" ]] && sAudio=""
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
  sLength="00:00:00.00"
  l=0
  for f in "${sFiles[@]}"; do
    [ "x$(echo "$f" | grep -iP "\||(\.($VIDEXT)$)")" == "x" ] && continue # allow archive strings through (match '|')
    #echo -ne "#$f$([ $level -gt 2 ] && echo '\n' || echo ' | ')"    
    if [ $level -eq 0 ]; then
      echo "#$f" && fnFileInfo $level "$f"
    else
      s=$(fnFileInfo $level "$f")
      echo -e "[$s]  \t$f"
      #[ $level -ge 3 ] && sLength=$(fnPositionAdd "$sLength" "$(echo "$s" | sed -n 's/^\[\(.*\)|.*$/\1/p')" 2>/dev/null)
      [ $level -ge 3 ] && sLength=$(fnPositionAdd "$sLength" "$(echo "$s" | cut -d'|' -f1)" 2>/dev/null)
    fi
    l=$[$l+1]
  done
  [[ $level -ge 3 && $l -gt 1 ]] && echo "[total duration: $sLength]"
}

fnFiles()
{
  #given a file name, return a tab delimited array of associated files in the local directory

  [ $DEBUG -ge 1 ] && echo "[debug fnFiles]" 1>&2

  bVerbose=1
  [ "x$1" == "xsilent" ] && bVerbose=0 && shift
  bInteractive=0
  [ "x$1" == "xinteractive" ] && bInteractive=1 && shift
  lDepth=1
  [ "x$1" == "xfull" ] && lDepth=10 && shift
  sSearch="$1" && shift
  sSearchPrev=""
  sSearchLast=""
  sSearchCustom=""
  lFound=0
  lFoundPrev=0
  lFoundFirst=0 #used to delay exit to 2nd successful search
  lFoundLast=0
  bAuto=1
  bMerge=0
  bSearch=1
  sType=""
  [ $# -gt 0 ] && sType="$1" && shift

  IFS=$'\n'
  while [ $bSearch -gt 0 ]; do
    bSearched=0
    bDiff=0
    if [[ $bInteractive -eq 0 && (
            ${#sSearch} -eq 0 || 
            (${#sSearch} -le $MINSEARCH && $lFoundLast -gt $lFoundFirst)) ]]; then 
      bSearch=0
    else
      if [[ $bAuto -eq 0 || 
           ($bAuto -eq 1 && ${#sSearch} -ge $MINSEARCH) ||
           ($bAuto -eq 1 && $bInteractive -eq 1) ]]; then
#           ($bAuto -eq 1 && ${#sSearch} -ge $MINSEARCH) ]]; then
        #whenever there is a difference between the new search and the previous search
        #replace the last search by the previous search
        [ $DEBUG -ge 2 ] && echo "[debug fnFiles] #1 sSearch: '$sSearch' sSearchCustom: '$sSearchCustom' sSearchPrev: '$sSearchPrev'  sSearchLast: '$sSearchLast'" 1>&2
        [ ! "x$sSearchCustom" == "x" ] && sSearchPrev="$sSearch" && sSearch="$sSearchCustom"
        if [[ ! "x$sSearch" == x$sSearchPrev || "x$sSearchLast" == "x" ]]; then
          sFiles=($(find ./ -maxdepth $lDepth -iregex '.*'"$(fnRegexp "$sSearch" "sed")"'.*\('"$(fnRegexp "$sType" "sed")"'\)$'))
          unset sFiles2
          for f in "${sFiles[@]}"; do
            [ -d "$f" ] &&
               sFiles2=("${sFiles2[@]}" $(find "$f"/ $sDepth -type f)) ||
               sFiles2=("${sFiles2[@]}" "$f")
          done
          sFiles=(${sFiles2[@]})
          lFound=${#sFiles[@]}
          if [ $lFound -ne $lFoundPrev ]; then
            bDiff=1
          elif [ $bAuto -eq 0 ]; then
            #compare old and new searches
            declare -A arr
            for f in "${sFilesPrev[@]}"; do arr["$f"]="$f"; done        
            for f in "${sFiles[@]}"; do [ "x${arr[$f]}" == "x" ] && bDiff=1 && break; done
          fi
          if [ $bDiff -eq 1 ]; then
            #keep record for revert
            lFoundLast=$lFoundPrev
            sFilesLast=(${sFilesPrev[@]})
            sSearchLast=$sSearchPrev
            [ $DEBUG -ge 2 ] && echo "[debug fnFiles] lFoundLast: '$lFoundLast', sSearchLast: '$sSearchLast', sFilesLast: '${sFilesLast[@]}'" 1>&2
          fi
          if [ $lFoundFirst -eq 0 ]; then lFoundFirst=$lFound; fi
          if [ $bMerge -eq 1 ]; then
            [ $DEBUG -ge 2 ] && echo "[debug fnFiles] lFoundLast: '$lFoundLast', sSearchLast: '$sSearchLast', sFilesLast: '${sFilesLast[@]}'" 1>&2
            sFiles2=("${sFiles[@]}") && sFiles=("${sFilesLast[@]}")
            declare -A arr
            for f in "${sFilesLast[@]}"; do arr["$f"]="$f"; done        
            for f in "${sFiles2[@]}"; do [ "x${arr[$f]}" == "x" ] && 
                                         sFiles=("${sFiles[@]}" "$f"); done
            lFound=${#sFiles[@]} 
          fi
        fi
      fi
      [ $DEBUG -ge 2 ] && echo "[debug fnFiles] #2 sSearch: '$sSearch' sSearchCustom: '$sSearchCustom' sSearchPrev: '$sSearchPrev'  sSearchLast: '$sSearchLast'" 1>&2
      if [[ ($bDiff -eq 1) ||
            ($bInteractive -eq 1 && $bAuto -eq 0) || 
            ($bAuto -eq 1 && ${#sSearch} -le $MINSEARCH) ]]; then
        [ $DEBUG -ge 1 ] && echo "[debug fnFiles] $sSearch == $sSearchPrev ??" 1>&2
        if [ $bVerbose -eq 1 ]; then
          if [[ $bAuto -eq 1 && $bDiff -eq 0 && ${#sSearch} -le $MINSEARCH && x$sSearch == x$sSearchPrev ]]; then
            echo "minimum search term length hit with '$sSearch'" 1>&2
          else
            echo -e "found ${#sFiles[@]} associated files searching with '$sSearch'" 1>&2
          fi
        fi
        if [ $bInteractive -gt 0 ]; then
          l=0; for f in "${sFiles[@]}"; do l=$[$l+1]; echo "  $f" 1>&2; [ $l -ge 10 ] && break; done
          if [ $lFound -gt 10 ]; then echo "..." 1>&2; fi
          echo -ne "search for more files automatically [y]es/[n]o" \
            "or manually [a]ppend/[c]lear? [r]evert matches or e[x]it? " 1>&2
          bRetry=1
          while [ $bRetry -gt 0 ]; do
            result=
            read -s -n 1 result 
            case "$result" in
              "y"|"Y") echo "$result" 1>&2; bRetry=0; bAuto=1; sSearchCustom="" ;;
              "n"|"N") echo "$result" 1>&2; bRetry=0; bSearch=0 ;;
              "a"|"A") echo "$result" 1>&2; bRetry=0; bAuto=0; bMerge=1; echo -n "search: " 1>&2; read sSearchCustom ;;
              "c"|"C") echo "$result" 1>&2; bRetry=0; bAuto=0; echo -n "search: " 1>&2; read sSearchCustom ;;
              "r"|"R") echo "$result" 1>&2; bRetry=0; bAuto=0; bMerge=0; sSearchCustom="$sSearchLast" ;;
              "x"|"X") echo "$result" 1>&2; return 1 ;;
            esac          
          done
        else
          if [[ (! "x$sSearchLast" == "x" && $lFound -gt 1) || ${#sSearch} -le $MINSEARCH ]]; then bSearch=0; fi
        fi
      else
        if [[ $bAuto -eq 1 && ${#sSearch} -le $MINSEARCH ]]; then
          if [ $bInteractive -eq 0 ]; then bSearch=0; fi
        fi
      fi
      sSearchPrev="$sSearch"
      sFilesPrev=("${sFiles[@]}")
      lFoundPrev=$lFound
      if [[ $bAuto -eq 1 && ${#sSearch} -gt $MINSEARCH ]]; then  sSearch=${sSearch:0:$[${#sSearch}-1]}; fi
      [ $DEBUG -ge 2 ] && echo "[debug fnFiles] #3 sSearch: '$sSearch' sSearchCustom: '$sSearchCustom' sSearchPrev: '$sSearchPrev'  sSearchLast: '$sSearchLast'" 1>&2
#      exit 1
    fi
  done 
  IFS=$IFSORG
    
  #verify files
  [ $DEBUG -ge 1 ] && echo "[debug fnFiles] sFiles: '${sFiles[@]}'" 1>&2
  bVerify=1
  IFS=$'\n'
  if [ $lFound -gt 0 ]; then
    if [ $bInteractive -eq 0 ]; then
      sFiles2=(${sFiles[@]})
    else
      echo -e "verify associations for matched files" 1>&2
      bAutoAdd=0
      unset sFiles2
      for f in "${sFiles[@]}"; do
        if [ -d "$f" ]; then
          for f2 in $(find "$f2" -type f); do
            bAdd=0
            if [ $bAutoAdd -gt 0 ]; then
              bAdd=1
            else
              echo -ne "  $f [(y)es/(n)o/(a)ll/(c)ancel/e(x)it] " 1>&2
              bRetry=1
              while [ $bRetry -gt 0 ]; do
                result=
                read -s -n 1 result 
                case "$result" in
                  "y"|"Y") echo "$result" 1>&2; bRetry=0; bAdd=1 ;;
                  "n"|"N") echo "$result" 1>&2; bRetry=0 ;;
                  "a"|"A") echo "$result" 1>&2; bRetry=0; bAdd=1; bAutoAdd=1 ;;
                  "c"|"C") echo "$result" 1>&2; bRetry=0; bVerify=0 ;;
                  "x"|"X") echo "$result" 1>&2; return 1 ;;
                esac             
              done             
            fi
            if [ $bAdd -eq 1 ]; then sFiles2=("${sFiles2[@]}" "$f"); fi             
            if [ $bVerify -eq 0 ]; then break; fi
          done 
        elif [ -f "$f" ]; then
          bAdd=0
          if [ $bAutoAdd -gt 0 ]; then
            bAdd=1
          else
            echo -ne "  $f [(y)es/(n)o/(a)ll/(c)ancel/e(x)it] " 1>&2
            bRetry=1
            while [ $bRetry -gt 0 ]; do
              result=
              read -s -n 1 result 
              case "$result" in
                "y"|"Y") echo "$result" 1>&2; bRetry=0; bAdd=1 ;;
                "n"|"N") echo "$result" 1>&2; bRetry=0 ;;
                "a"|"A") echo "$result" 1>&2; bRetry=0; bAdd=1; bAutoAdd=1 ;;
                "c"|"C") echo "$result" 1>&2; bRetry=0; bVerify=0 ;;
                "x"|"X") echo "$result" 1>&2; return 1 ;;
              esac 
            done
          fi
          if [ $bAdd -eq 1 ]; then sFiles2=("${sFiles2[@]}" "$f"); fi             
          if [ $bVerify -eq 0 ]; then break; fi
        fi
      done
    fi 
  fi
  IFS=$IFSORG

  [ $DEBUG -ge 1 ] && echo "[debug fnFiles] sFiles2: '${sFiles2[@]}'" 1>&2
 
  if [[ ! "x${sFiles2}" == "x" && ${#sFiles2[@]} -gt 0 ]]; then
    [ $bVerbose -eq 1 ] && fnLog "associated files for '$sSearch': '${sFiles2[@]}'"
    #return '\n' delimited strings
    for f in "${sFiles2[@]}"; do echo "$f"; done
  fi

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
    if [ -d "$PATHARCHIVELISTS" ]; then
      if [ "$REGEX" -eq 0 ]; then
        arr=($(grep -ri "$sSearch" "$PATHARCHIVELISTS" 2>/dev/null))
      else    
        arr=($(grep -rie "$sSearch" "$PATHARCHIVELISTS" 2>/dev/null))
      fi 
      #filter results
      if [[ ${#arr[@]} -gt 0 && "x$arr" != "x" ]]; then
        arr2=
        for s in ${arr[@]}; do
          s="$(echo "$s" | sed -n 's/^\([^:~]*\):\([^|]*\).*$/\1|\2/p')"
          if [ "$REGEX" -eq 0 ]; then
            s="$(echo "$s" | grep -i "$sSearch" 2>/dev/null)"
          else
            s="$(echo "$s" | grep -ie "$sSearch" 2>/dev/null)"
          fi          
          if [ "x$s" != "x" ]; then
            [ "x${arr2}" == "x" ] && arr2=("$s") || arr2=("${arr2[@]}" "$s")
          fi
        done
        #merge results
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
          [[ ${#files[@]} -gt 0 && "x$files" != "x" ]] && files=(${files[@]} ${arr2[@]}) || files=(${arr2[@]})
        fi
      fi
    else
      echo "no archive lists found at: '$PATHARCHIVELISTS'" 1>&2
    fi
    
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
    ##format type:name[:info] -> title:file[:search]
    sPlaylist=
    for s in "${sMatched[@]}"; do	   
      [ "x$(echo "$s" | grep '|')" == "x" ] && s="file|$s"
      type="${s%%|*}" && s=${s:$[${#type}+1]} && type="${type##*/}"
      name="${s%%|*}" && s=${s:$[${#name}+1]}
      s=""
      prepend=0
#        title="$(echo "$name" | sed -n 's/^.*\/\([^[]*\)[. ]\+.*$/\1/p')"
      title="${name##*/}" && title="${title%[*}" && title="$(echo "$title" | sed 's/\(^\.\|\.$\)//g')" #alternative approach below
      case "$type" in
        "dvd"|"dvds") s="$title|dvdnav:////dev/dvd"; prepend=1 ;;
        "vcd"|"vcds") s="$title|vcd:////dev/dvd"; prepend=1 ;;
        "cd"|"cds") s="$title|/dev/dvd|$sSearch"; prepend=1 ;;
        "file"|"files") s="$title|$name" ;;
        *) s="$title|$ROOTDISK$type/$name" ;; #convert archive entry to location 
      esac
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
      if [ "x$(echo "$file" | grep "/dev/dvd")" != "x" ]; then
        #play?
        echo -n "play '$title'? [(y)es/(n)o/e(x)it]:  "
        bRetry=1                
        while [ $bRetry -eq 1 ]; do
          echo -en '\033[1D\033[K'
          read -n 1 -s result
          case "$result" in
            "x" | "X") echo -n $result; bRetry=0; echo ""; exit 0 ;;
            "n" | "N") echo -n $result; bRetry=0; file="" ;;
            "y" | "Y") echo -n $result; bRetry=0 ;;
            *) echo -n " " 1>&2
          esac
        done
        echo ""
        if [ "x$file" != "x" ]; then
          played=0
          bRetry=1
          sFiles=
          while [ $bRetry -eq 1 ]; do
            [ $played -gt 0 ] && NEXT="next "
            if [ "${#sFiles}" -gt 0 ]; then
              #files to play
              if [ "x$file" == "x/dev/dvd" ]; then
                type="cd" #cds
                echo "playing '$title' [cd]" 1>&2
                for f in "${sFiles[@]}"; do DISPLAY=$display $cmdplay $cmdplay_options $@ "$ROOTISO$f"; done
                umount "$ROOTISO" 2>/dev/null
              else
                type="${file:0:3}" #dvds/vcds
                echo "playing '$title' []" 1>&2
                DISPLAY=$display $cmdplay $@ $cmdplay_options "${sFiles[0]}"
              fi
              played=$[$played+${#sFiles[@]}]
              sFiles=             
            else
              if [[ ! -t $(fnDriveStatus) || $played -gt 0 ]]; then
                #block until disc is inserted
                echo -n "[user] insert "$NEXT"disk for '$title' [(r)etry|(e)ject|(l)oad|e(x)it]:  "
                bRetry2=1                
                while [ $bRetry2 -eq 1 ]; do
                  echo -en '\033[1D\033[K'
                  read -n 1 -s result
                  case "$result" in
                    "r" | "R") echo -n $result; [ -t $(fnDriveStatus) ] && bRetry2=0 ;;
                    "e" | "E") echo -n $result; umount /dev/dvd >/dev/null 1>&2; [ -t $(fnDriveStatus) ] && eject -T >/dev/null 1>&2 ;;
                    "l" | "L") echo -n $result; [ ! -t $(fnDriveStatus) ] && eject -t 2>/dev/null ;;
                    "x" | "X") echo -n $result; bRetry=0; bRetry2=0; file="" ;;
                    *) echo -n " " 1>&2
                  esac          
                done
                echo ""
              fi
              if [ "x$file" != "x" ]; then               
                if [ "x$file" == "x/dev/dvd" ]; then
                  #mount and search for files
                  mount -t auto -o ro /dev/dvd "$ROOTISO" 2>/dev/null && sleep 1
                  cd $ROOTISO
                  IFS=$'\n'
                  sFiles=($(fnFiles silent full "$search" "$VIDEXT"))
                  x=$?
                  if [ ${#sFiles[@]} -eq 0 ]; then
                    sFiles=($(fnFiles interactive full "$search" "$VIDEXT"))
                    x=$?
                  fi
                  IFS=$IFSORG
                  cd - >/dev/null 2>&1
                  [ $x -ne 0 ] && bRetry=0 && sFiles= && continue
                else
                  #specify the track for vcds
                  if [ "${file:0:3}" == "vcd" ]; then
                    #ID_VCD_TRACK_1_MSF=00:16:63
                    IFS=$'\n'; sTracks=($($CMDINFOMPLAYER "$file" | sed -n 's/^ID_VCD_TRACK_\([0-9]\)_MSF=\([0-9:]*\)$/\1|\2\.0/p')); IFS=$IFSORG
                    if [ ${#sTracks[@]} -gt 0 ]; then
                      for s in "${sTracks[@]}"; do
                        sTrackTime2=$(fnPositionTimeToNumeric "${s##*|}")
                        if [[ "x$sTrack" == "x" || $(math_ "\$gt($sTrackTime2, $sTrackTime)") -eq 1 ]]; then
                          sTrack="${s%%|*}"
                          sTrackTime="$sTrackTime2"
                        fi
                      done                          
                    fi
                    [ "x$sTrack" == "x" ] && sTrack="1"                    
                    sFiles=("$(echo "$file" | sed 's|vcd://|vcd://'$sTrack'|')")
                  else
                    sFiles=("$file")
                  fi
                fi
              fi
            fi
          done
        fi
      else
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
            #block whilst file doesn't exist      
            bRetry=1                
            while [ $bRetry -eq 1 ]; do
              if [ -e "$file" ]; then
                bRetry=0
              else 
                echo -n "[user] file '$file' does not exist? [(r)etry/(s)kip/e(x)it]:  "
                bRetry2=1                
                while [ $bRetry2 -eq 1 ]; do
                  echo -en '\033[1D\033[K'
                  read -n 1 -s result
                  case "$result" in
                    "x" | "X") echo -n $result; bRetry=0; bRetry2=0; echo ""; exit 0 ;;
                    "s" | "S") echo -n $result; bRetry=0; bRetry2=0 ;;
                    "r" | "R") echo -n $result; bRetry2=0 ;;
                    *) echo -n " " 1>&2
                  esac
                done
                echo ""
              fi
            done
            #add to playlist
            if [[ -e "$file" && "x$file" != "x" ]]; then
              [ "x${sFiles[@]}" == "x" ] && sFiles=("$file") || sFiles=("${sFiles[@]}" "$file")
            fi
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

fnArchive()
{
  #list files at target for archive purposes

  CWD="$PWD/"
  target="$PATHARCHIVELISTS"
  level=0
  [[ $# -gt 0 && "x$(echo "$1" | sed -n '/^[0-9]\+$/p')" != "x" ]] && level=$1 && shift
  [ $# -gt 0 ] && source="$1" && shift || source="."
  [ -d "$source" ] && cd "$source"
  [ "x${source:$[${#source}-1]:1}" == "x/" ] && source="${source:0:$[${#source}-2]}" && shift || source="$PWD"
  [ $# -gt 0 ] && file="$1" && shift || file="${source##*/}"
  
  source="$source/"
  if [ $level -eq 0 ]; then
    find . -type f -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)' | sort -i > "$target$file"
  else
    IFS=$'\n'; sFiles=($(find . -type f -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)' | sort -i)); IFS=$IFSORG
    bAppend=0
    for f in "${sFiles[@]}"; do
      s="$f|$(fnFileInfo $level "$f")"
      if [ $bAppend -eq 0 ]; then
        echo "$s" > "$target$file" && bAppend=1
      else
        echo "$s" >> "$target$file"
      fi
    done    
  fi
  echo "updated archive list: '$target$file'"
  cd $CWD
}

#args
[ $# -lt 1 ] && help && exit 1

#REGEX
[[ $# -gt 1 && "x$1" == "xregex" ]] && REGEX=1 && shift

if [ "x$(echo $1 | sed -n 's/^\('\
's\|search\|'\
'p\|play\|'\
'i\|info\|'\
'a\|archive'\
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
  "a"|"archive") fnArchive "${args[@]}" ;;  
  *) help ;;
esac
