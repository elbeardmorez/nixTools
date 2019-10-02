#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG=$IFS
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}

CWD="$PWD/"

RC_FILE="${RC_FILE:-"$HOME/.nixTools/$SCRIPTNAME"}"
[ -e "$RC_FILE" ] && . "$RC_FILE"

ROOTDISK="${ROOTDISK:-"/media/"}"
ROOTISO="${ROOTISO:-"/media/iso/"}"
PATHMEDIA="${PATHMEDIA:-"$HOME/media/"}"
PATHMEDIATARGETS="${PATHMEDIATARGETS:-""}"
PATHRATINGSDEFAULT="${PATHRATINGSDEFAULT:-"${PATHMEDIA}watched/"}"
PATHARCHIVELISTS="${PATHARCHIVELISTS:-"${PATHMEDIA}/archives/"}"

CHARPOSIX='][^$?*+'
CHARPERL='].[)(}{*|/-'
CHARSED='].[|/-'
CHARGREP='].['
MINSEARCH=3
VIDEXT="avi|mpg|mpeg|mkv|mp4|flv|webm|m4v|wmv"
VIDXEXT="srt|idx|sub|sup|ssa|smi"
EXTEXT="nfo|rar|txt|png|jpg|jpeg|xml"
VIDCODECS="flv=flv,flv1|x265=x265,hevc,h265|x264=x264,h264|xvid|divx=divx,dx50,div3,div4,div5,divx\.5\.0|msmpg=msmpeg4|mpeg2|vpx=vp7,vp8|wvc1"
AUDEXT="mp3|ogg|flac|ape|mpc|wav"
AUDCODECS="opus|vbs=vorbis|aac|dts|ac3|mp3=mp3,mpeg-layer-3|mp2|wma"
AUDCHANNELS="1.0ch=mono|2.0ch=2.0,2ch,2 ch,stereo|3.0ch=3.0|4.0ch=4.0|5.0ch=5.0|5.1ch=5.1|6.1ch=6.1|7.1ch=7.1|10.1ch=10.1"
FILTERS_EXTRA="${FILTERS_EXTRA:-""}"

CMDMD="mkdir -p"
CMDMV="mv -i"
CMDCP="cp -ar"
CMDRM="rm -rf"
CMDPLAY="${CMDPLAY:-"mplayer"}"
CMDPLAY_OPTIONS="${CMDPLAY_OPTIONS:-"-tv"}"
CMDPLAY_PLAYLIST_OPTIONS="${CMDPLAY_PLAYLIST_OPTIONS:-"-p "}"
CMDINFOMPLAYER="${CMDINFOMPLAYER:-"mplayer -identify -frames 0 -vc null -vo null -ao null"}"
CMDFLVFIXER="${CMDFLVFIXER:-"flvfixer.php"}"
PLAYLIST="${PLAYLIST:-"/tmp/$CMDPLAY.playlist"}"
LOG="${LOG:-"/var/log/$SCRIPTNAME"}"

# globals options
declare regexp; regexp=0

declare -a args
declare option; option="play"

help() {
  echo -e "SYNTAX: $SCRIPTNAME [OPTION]
\nwhere OPTION:
\n  -p|--play TARGET  : play media file(s) found at TARGET
\n    TARGET  : a file, directory or a partial name to search for. see
              'search' for supported strings
\n  -s|--search [OPTION] SEARCH : search for file(s) in known locations
\n    OPTION:
      -i|--interactive  : prompt to complete search on first valid
                          results set
      -ss|--substring-search  : search progressively shorter substring
                                of the search term until match
      -x|--extensions EXTENSIONS  : override default pipe-delimited
                                    ('|') supported a/v extensions set
    SEARCH  : a (partial) match term. both 'glob' and 'regular
              expression' (PCRE) search strings are supported. an
              initial parse for unescaped special characters is made.
              if no such characters, or only '*' characters are found,
              the search string will be deemed a glob, otherwise it
              will be deemed a literal string and escaped prior to
              regular expression search. use of the global '--regexp'
              option circumvents this escaping
\n  -i|--info [LEVEL]  : output formatted information on file(s)
\n    LEVEL  : number [1-5] determining the verbosity of information
             output
\n  -a|--archive [LEVEL] [SOURCE]
    : recursively search a directory and list valid media files with
      their info, writing all output to a file
\n    LEVEL  : number [1-5] determining the verbosity of information
             output
    SOURCE  : root directory containing media files to archive
\n  -str|--structure [OPTION] SEARCH [FILTER [FILTER2.. [FILTERx]]]
    : create a standardised single / multi-file structure for matched
      file(s) under the current working directory
\n    OPTION:
      -s|--silent  : suppress info message output
    SEARCH  : a (partial) match term
    FILTER  : string(s) to remove from matched file names in a multi-
              file structure
\n  -r|--rate SEARCH RATING  : rate media and move structures to the
                             nearest ratings hierarchies
\n    SEARCH  : a (partial) match term
    RATING  : numeric rating (eg. 1-10), to push the structure to /
              under in a ratings hierarchy
\n  -rec|--reconsile LIST  : match a list of names / files in list to
                           media at known locations and write results
                           to an adjacent file
\n    LIST  : file containing names / files strings to search for
\n  -f|--fix TARGET  : fix a stream container
\n    TARGET  : the broken flv media file
\n  --kbps VSIZE ASIZE LENGTH  : calculate an approximate vbr for a
                               target file size
\n    VSIZE[M|b]  : target video size in either megabytes ('M' suffix)
                  or bytes ('b' suffix / default)
    ASIZE[M|b]  : target audio size in either megabytes ('M' suffix)
                  or bytes ('b' suffix / default)
    LENGTH[m|s]  : length of stream in either minutes ('m' suffix /
                   default) or seconds ('s' suffix)
\n  -rmx|--remux TARGET [PROFILE] [WIDTH] [HEIGHT] [VBR] [ABR]
                        [PASSES] [VSTREAM] [ASTREAM]
    : ffmpeg wrapper for changing video dimensions and / or a/v codecs
\n    TARGET  : file to remultiplex
    PROFILE  : profile name (default: '2p6ch')
    WIDTH  : video width dimension (default: auto)
    HEIGHT  : video height dimension (default: auto)
    VBR  : video bitrate (default: 1750k)
    ABR  : audio bitrate (default: 320k)
    PASSES  : perform x-pass conversion of stream (x: 1 or 2)
    VSTREAM  : set video stream number (default: 0)
    ASTREAM  : set audio stream number (default: 0)
\n  -syn|--sync TARGET OFFSET  : (re-)synchronise a/v streams by
                                 applying an offset
\n    TARGET  : file to synchronise
    OFFSET  : numeric offset in milliseconds
\n  -e|--edit [TARGET] [FILTER]  : demux / remux routine
\n    TARGET  : directory containing video files to demux or multiple
            demuxed stream files (*.vid | *.aud) to concatenate and
            multiplex (default: '.')
    FILTER  : whitelist match expression for sed (default: '.*')
\n  -n|--names SET [LIST]  : rename a set of files, based on a
                           one-to-one list of pipe ('|') delimited
                           templates of the form '[#|]#|NAME' in a
                           file
\n    SET  : common prefix for all resultant file names
    LIST  : file containing templates (default: './names')
\n  -pl|--playlist LIST  : interactively cycle a list of filenames and
                         play the subset which begins with the
                         selected item
\n    LIST  : file containing file paths to cycle
\n  --rip TITLE  : extract streams from dvd media
\n    TITLE  : name used for output files
\n# global options:
  -rx|--regexp  : assume valid regular expression (PCRE) search term
\n# environment variables:
\n## global
DEBUG  : output debug strings of increasingly verbose nature
         (i.e. DEBUG=2)
TEST  : '--structure'|'--names', perform dry-run (i.e. TEST=1)
ROOTDISK  : root directory containing disk mounts (default: '/media')
ROOTISO  : root of cd / dvd mount (default: '/media/iso')
PATHMEDIA  : path to media store (default: '\$HOME/media')
PATHMEDIATARGETS  : pipe-delimited ('|') list of targets paths, full
                    paths, '\$PATHMEDIA' relative paths and glob names
                    supported
PATHRATINGSDEFAULT  : path to ratings structure
                      (default: '\$PATHMEDIA/watched')
PATHARCHIVELISTS  : path to archive list(s), either full path(s) or
                    '\$PATHMEDIATARGETS' relative path(s), falling back
                    to '\$PATHMEDIA' relative path(s) supported
                    (default: 'archives/')
\n## option specific
FILTERS_EXTRA [--structure]  : additional string filter expession for
                               sed of the form 'SEARCH/REPLACE'
VIDEO [--rip]  : override subtitle track extracted (default: 1)
AUDIO [--rip]  : override subtitle track extracted (default: 1)
SUBS [--rip]  : override subtitle track extracted (default: 1)
CMDPLAY [--play|--playlist]  : player binary (default: 'mplayer')
CMDPLAY_OPTIONS [--play|--playlist] :  player options (default: '-tv')
CMDPLAY_PLAYLIST_OPTIONS  [--play|--playlist]
  : player specific option required for playlist mode (default: '-p ')
CMDFLVFIXER [--fix]  : 'flvfixer' script path
PLAYLIST [--playlist]
  : playlist file (default: '/tmp/\$CMDPLAY.playlist)
" 1>&2
}

fn_log() {
  [ $DEBUG -ge 2 ] && echo "[debug fn_log]" 1>&2

  echo "$@" | tee $LOG 1>&2
}

fn_display() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_display]" 1>&2

  display="${DISPLAY_:-"$DISPLAY"}"
  echo $display
}

fn_drive_status() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_drive_status]" 1>&2

  [ -z "$(cdrecord -V --inq dev=/dev/dvd 2>&1 | grep "medium not present")" ] && echo 1 || echo -1
}

fn_regexp() {
  [ $DEBUG -ge 2 ] && echo "[debug fn_regexp]" 1>&2

  # escape reserved characters
  s_exp="$1" && shift
  s_type="${1:-"posix"}"
  if [ $DEBUG -ge 2 ]; then
    s_="$(awk 'BEGIN{print toupper("'"$s_type"'")}')"
    echo "[debug fn_regexp], s_exp: '$s_exp', s_type: '$s_type', CHAR$s_: '"$(eval "echo '$CHAR$s_'")"'" 1>&2
  fi
  case "$s_type" in
    "perl") s_exp=$(echo "$s_exp" | sed 's/\(['$CHARPERL']\)/\\\1/g') ;;
    "grep") s_exp=$(echo "$s_exp" | sed 's/\(['$CHARGREP']\)/\\\1/g') ;;
    "sed") s_exp=$(echo "$s_exp" | sed 's/\(['$CHARSED']\)/\\\1/g') ;;
    "posix") s_exp=$(echo "$s_exp" | sed 's/\(['$CHARPOSIX']\)/\\\1/g') ;;
  esac
  [ $DEBUG -ge 2 ] && echo "[debug fn_regexp] #2, s_exp: '$s_exp'" 1>&2
  echo "$s_exp"
}

fn_position_time_valid() {
  [ $DEBUG -ge 2 ] && echo "[debug fn_position_time_valid]" 1>&2

  pos="$1"
  if [ -z "$(echo "$pos" | sed -n 's|^\([+-/*]\{,1\}\s*[0-9:]*[0-9]\{2\}:[0-9]\{2\}[:,.]\{1\}[0-9]\{1,\}\)$|\1|p')" ]; then
    echo "illegal position format. require '00:00:00[.,:]0[00...]'" 1>&2
    echo 0
  else
    echo 1
  fi
}

fn_position_numeric_valid() {
  [ $DEBUG -ge 2 ] && echo "[debug fn_position_numeric_valid]" 1>&2

  num="$1"
  [ -z "$(echo "$num" | sed -n '/.*[.,:]\{1\}[0-9]\+/p')" ] && num="$num.0"
  if [ -z "$(echo "$num" | sed -n 's|^\([+-/*]\{,1\}\s*[0-9]\+[:,.]\{1\}[0-9]\{1,\}\)$|\1|p')" ]; then
    echo "illegal number format. require '0[.,:]0[00...]'" 1>&2
    echo 0
  else
    echo 1
  fi
}

fn_position_numeric_to_time() {
  # convert float to positon string

  [ $DEBUG -ge 2 ] && echo "[debug fn_position_numeric_to_time]" 1>&2

  s_prefix="$(echo "$1" | sed -n 's/^\([^0-9]\+\).*$/\1/p')"
  l_num="${1:${#s_prefix}}"
  shift
  [ $(fn_position_numeric_valid "$l_num") -eq 0 ] && return 1
  l_token="-1" && [ $# -gt 0 ] && l_token=$1 && shift
  s_delim_milliseconds="." && [ $# -gt 0 ] && s_delim_milliseconds="$1" && shift
  #IFS='.,:' && s_tokens=($(echo "$s_pos")) && IFS=$IFSORG
  #l_tokens=${l_tokens:-${#s_tokens[@]}}
  ## force emtpy tokens if required
  #if [ $l_tokens -ne ${#s_tokens[@]} ]; then
  #  for l in $(seq ${#s_tokens[@]} 1 $l_tokens); do s_tokens[$((l - 1))]="00"; done
  #fi
  IFS='.,:' && s_tokens=($(echo "$l_num")) && IFS=$IFSORG

  s_total=$(printf "%.3f" "0.${s_tokens[1]}" | cut -d'.' -f2) # milliseconds
  l_carry=${s_tokens[0]} # the rest!
  local l
  while [[ $(echo "$l_carry > 0" | bc) -eq 1 || $l -lt $l_token || $l -le 1 ]]; do
    case $l in
      1) # seconds
        l_carry2=$(echo "scale=0;($l_carry)/60" | bc)
        s_total="$(printf "%02d" $(echo "scale=0;($l_carry-($l_carry2*60))" | bc)).$s_total"
        l_carry=$l_carry2
        ;;
      2) # minutes
        l_carry2=$(echo "scale=0;($l_carry)/60" | bc)
        s_total="$(printf "%02d" $(echo "scale=0;($l_carry-($l_carry2*60))" | bc)):$s_total"
        l_carry=$l_carry2
        ;;
      3) # hours
        l_carry2=$(echo "scale=0;($l_carry)/24" | bc)
        s_total="$(printf "%02d" $(echo "scale=0;($l_carry-($l_carry2*24))" | bc)):$s_total"
        l_carry=$l_carry2
        ;;
      4) # days
        s_total="$l_carry:$s_total"
        l_carry=0
        ;;
    esac
    l=$((l + 1))
  done
  echo "$s_prefix$(echo "$s_total" | sed 's/\./'$s_delim_milliseconds'/')"
}

fn_position_time_to_numeric() {
  # convert s_positon string to float

  [ $DEBUG -ge 2 ] && echo "[debug fn_position_time_to_number]" 1>&2

  s_prefix="$(echo "$1" | sed -n 's/^\([^0-9]\+\).*$/\1/p')"
  s_pos="${1:${#s_prefix}}"
  [ $(fn_position_time_valid "$s_pos") -eq 0 ] && return 1
  IFS='.,:' && s_tokens=($(echo "$s_pos")) && IFS=$IFSORG
  l_total=0
  l_scale=3
  local l
  for l in $(seq 0 1 $((${#s_tokens[@]} - 1))); do
    s_token=${s_tokens[$((${#s_tokens[@]} - l - 1))]}
    #echo "$s_token"
    case $l in
      0) l_scale=${#s_token}; l_total=$(echo "scale=$l_scale;$s_token/(10^${#s_token})" | bc) ;; # milliseconds
      1) l_total=$(echo "scale=$l_scale;$l_total+$s_token" | bc) ;; # seconds
      2) l_total=$(echo "scale=$l_scale;$l_total+($s_token*60)" | bc) ;; # minutes
      3) l_total=$(echo "scale=$l_scale;$l_total+($s_token*3600)" | bc) ;; # hours
      4) l_total=$(echo "scale=$l_scale;$l_total+($s_token*24*3600)" | bc);; # days
    esac
  done
  echo $s_prefix$l_total
}

fn_position_add() {
  # iterate through : delimited array, adding $2 $1 ..carrying an extra
  # 1 iff length of result is greater than the length of either ot the
  # original numbers

  [ $DEBUG -ge 2 ] && echo "[debug fn_position_add]" 1>&2

  base="$1"
  bump="$2"
  [[ $(fn_position_time_valid "$base") -eq 0 || $(fn_position_time_valid "$bump") -eq 0 ]] && echo "$base" &&  return 1

  IFS=$'\:\,\.'
  a_base=($(echo "$base"))
  a_bump=($(echo "$bump"))
  IFS=$IFSORG
  s_final=""
  l_carry=0
  l=${#a_base[@]}
  while [ $l -gt 0 ]; do
    l_base=${a_base[$((l - 1))]}
    l_bump=${a_bump[$((l - 1))]}
    l_res=$((10#$l_base+10#$l_bump+10#$l_carry))
    if [ ${#l_base} -eq 2 ]; then
      s_token=$((10#$l_res % 60))
      l_carry=$(($((10#$l_res - 10#$l_res % 60))/60))
    else
      if [ ${#l_res} -gt ${#l_base} ]; then
        s_token=${l_res:1:${#l_base}}
        l_carry=1
      else
        s_token=$l_res
        l_carry=0
      fi
    fi
    # re-pad token
    if [ ${#s_token} -lt ${#l_base} ]; then
      ll=${#s_token}
      while [ ${#s_token} -lt ${#l_base} ]; do
        s_token="0"$s_token
      done
    fi
    if [ -z "$s_final" ]; then
      s_final=$s_token
    else
      s_final="$s_token${base:$((${#base[0]} - ${#s_final[0]} - 1)):1}$s_final"
    fi
    l=$((l - 1))
  done
  echo "$s_final"
}

fn_file_stream_info() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_file_stream_info]" 1>&2

  # via ffmpeg
  s_file="$1"
  IFS=$'\n'; s_info=($(ffmpeg -i "file:$s_file" 2>&1 | grep -iP "stream|duration")); IFS=$IFSORG
  [ ${#s_info[@]} -gt 0 ] && s_info=("# ffmpeg #" "${s_info[@]}")

  # via mplayer
  #ID_VCD_TRACK_1_MSF=00:16:63.0
  IFS=$'\n'; s_info2=($($CMDINFOMPLAYER "$s_file" 2>/dev/null | sed -n '/^\(VIDEO\|AUDIO\).*$/p')); IFS=$IFSORG
  [ ${#s_info2[@]} -gt 0 ] && s_info2=("# mplayer #" "${s_info2[@]}")
  IFS=$'\n'; s_tracks=($($CMDINFOMPLAYER "$s_file" 2>/dev/null | sed -n 's/^ID_VCD_TRACK_\([0-9]\)_MSF=\([0-9:]*\)$/\1|\2/p')); IFS=$IFSORG
  if [ ${#s_tracks[@]} -gt 0 ]; then
    s_track_time2=
    for s in "${s_tracks[@]}"; do
      s_track_time2=$(fn_position_time_to_numeric "${s##*|}")
      if [[ -z "$s_track" || $(math_ "\$gt($s_track_time2, $s_track_time)") -eq 1 ]]; then
        s_track="${s%%|*}"
        s_track_time="$s_track_time2"
      fi
    done
    s="duration: $(fn_position_numeric_to_time $s_track_time),"
    [ ${#s_info2[@]} -eq 0 ] && s_info2=("# mplayer #" "$s") || s_info2=("${s_info2[@]}" "$s" "${s_info2[@]}")
    [ ${#s_info[@]} -eq 0 ] && s_info="${s_info2[@]}" || s_info=("${s_info[@]}" "${s_info2[@]}")
  fi

  # via mkvtools
  if [ "x${s_file##*.}" = "xmkv" ]; then
    IFS=$'\n'; s_info2=($(mkvmerge --identify "$s_file" 2>&1)); IFS=$IFSORG
    [ ${#s_info2[@]} -gt 0 ] && s_info2=("# mkvtools #" "${s_info2[@]}")
    [ ${#s_info[@]} -eq 0 ] && s_info="${s_info2[@]}" || s_info=("${s_info[@]}" "${s_info2[@]}")
  fi

  for s in "${s_info[@]}"; do echo "$s"; done
}

fn_file_info() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_file_info]" 1>&2

  # level
  # 0 raw
  # 1 vid.aud.ch
  # 2 length|vid.aud.ch
  # 3 length|size|vid.aud.ch
  # 4 length|fps|size|vid.aud.ch

  # defaults
  s_length_default="00:00:00.000|"
  s_fps_default="x.xfps|"
  s_size_default="0x0|"
  s_video_default="vidxxx"
  s_video_bitrate_default=".0kb/s"
  s_audio_default=".audxxx"
  s_audio_bitrate_default=".0kb/s"
  s_channels_default=".x.xch"

  s_length="$s_length_default"
  s_fps="$s_fps_default"
  s_size="$s_size_default"
  s_video="$s_video_default"
  s_video_bitrate="$s_video_bitrate_default"
  s_audio="$s_audio_default"
  s_audio_bitrate="$s_audio_bitrate_default"
  s_channels="$s_channels_default"

  [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/^[0-9]\+$/p')" ]] && level=$1 && shift || level=1
  s_file="$1" && shift
  # archived?
  if [ ! -f "$s_file" ]; then
    # *IMPLEMENT
    # return requested level of info
    s_file_info=$(grep "$(fn_regexp "${s_file##*|}" "grep")" "${s_file%%|*}")
    #echo "${s_file_info:${#s_file}}" && return
    [ -z "${s_file_info}" ] && echo "${s_file_info#*|}" || echo "$s_video$s_audio$s_channels"
    return
  fi

  # filetype
  audio_types="$(echo "$AUDCODECS" | sed 's/[,.=|]/\\\|/g')"
  s_type="video" && [ -n "$(echo "${s_file##*.}" | sed -n '/'$audio_types'/p')" ] && s_type="audio"

  s_file_stream_info="$(fn_file_stream_info "$s_file")"
  IFS=$'\n'; s_info=($(echo -e "$s_file_stream_info")); IFS=$IFSORG
  for s in "${s_info[@]}"; do
    case $level in
      0)
        echo "$s"
        ;;
      *)
        if [ -n "$(echo "$s" | sed -n '/^.*duration.*$/Ip')" ]; then
          if [ $level -gt 1 ]; then
            # parse duration
            s_length2=$(echo "$s" | sed -n 's/^.*duration:\s\([0-9:.]\+\),.*$/\1/Ip')
            [ -n "$s_length2" ] && s_length="$s_length2|"
          fi
        elif [ -n "$(echo "$s" | sed -n '/^.*video.*$/Ip')" ]; then
          if [ "x$s_video" = "x$s_video_default" ]; then
            [ $DEBUG -ge 2 ] && echo "#fn_file_info, IFS='$IFS'" 1>&2
            IFS=$'|'; a_codecs=($(echo "$VIDCODECS")); IFS=$IFSORG
            [ $DEBUG -ge 2 ] && echo "[debug] fn_file_info #2, IFS='$IFS'" 1>&2
            [ $DEBUG -ge 1 ] && echo "[debug] fn_file_info, codecs: ${#a_codecs[@]}, codecs: '${a_codecs[@]}'" 1>&2
            #[ $TEST -eq 1 ] && return 0
            for s2 in "${a_codecs[@]}"; do
              if [ -z "$(echo "'$s2'" | sed -n '/\=/p')" ]; then
                [ -n "$(echo "'$s'" | sed -n '/'"$(fn_regexp "$s2" "sed")"'/Ip')" ] && s_video="$s2"
              else
                # iterate and match using a list of codec descriptions
                IFS=$','; a_codec_info=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${a_codec_info[@]}"; do
                  [ -n "$(echo """$s""" | sed -n '/'"$(fn_regexp "$s3" "sed")"'/Ip')" ] && s_video="${s2%=*}" && break
                done
              fi
              [ "x$s_video" != "x$s_video_default" ] && break
            done
          fi
          if [[ $level -gt 2 && "x$s_size" == "x0x0|" ]]; then
            # parse size
            s_size2=$(echo "'$s'" | sed -n 's/^.*[^0-9]\([0-9]\+x[0-9]\+\).*$/\1/p')
            [ -n "$s_size2" ] && s_size="$s_size2|"
          fi
          if [[ $level -gt 3 && "x$s_fps" == "x$s_fps_default" ]]; then
            # parse fps
            s_fps2="$(echo "'$s'" | sed -n 's/^.*\s\+\([0-9.]\+\)\s*tbr.*$/\1/p')"
            [ -z "$s_fps2" ] && s_fps2="$(echo "$s" | sed -n 's/^.*\s\+\([0-9.]\+\)\sfps.*$/\1/p')"
            [ -n "$s_fps2" ] && s_fps2="$(echo "$s_fps2" | sed 's/\(\.\+0*\)$//')"
            [ -n "$s_fps2" ] && s_fps=$s_fps2"fps|"
          fi
          [ $DEBUG -ge 1 ] && echo "[debug] fn_file_info, s_fps: '$s_fps', s_size: '$s_size'" 1>&2
        elif [ -n "$(echo "'$s'" | sed -n '/^.*audio.*$/Ip')" ]; then
          if [ "x$s_audio" = "x$s_audio_default" ]; then
            IFS=$'|'; a_codecs=($(echo "$AUDCODECS")); IFS=$IFSORG
            for s2 in "${a_codecs[@]}"; do
              if [ -z "$(echo "'$s2'" | sed -n '/\=/p')" ]; then
                [ -n "$(echo "'$s'" | sed -n '/'"$(fn_regexp "$s2" "sed")"'/Ip')" ] && s_audio="$s2"
              else
                # iterate and match using a list of codec descriptions
                IFS=$','; a_codec_info=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${a_codec_info[@]}"; do
                  [ -n "$(echo "'$s'" | sed -n '/'"$(fn_regexp "$s3" "sed")"'/Ip')" ] && s_audio="${s2%=*}" && break
                done
              fi
              [ "x$s_audio" != "x$s_audio_default" ] && s_audio=".$s_audio" && break
            done
          fi
          if [ "x$s_channels" = "x$s_channels_default" ]; then
            IFS=$'|'; a_codecs=($(echo "$AUDCHANNELS")); IFS=$IFSORG
            for s2 in "${a_codecs[@]}"; do
              if [ -z "$(echo "$s2" | sed -n '/\=/p')" ]; then
                [ -n "$(echo "'$s'" | sed -n '/[^0-9]'"$(fn_regexp "$s2" "sed")"'[^0-9]/Ip')" ] && s_channels="$s2"
              else
                # iterate and match using a list of codec descriptions
                IFS=$','; a_codec_info=($(echo "${s2#*=}" )); IFS=$IFSORG
                for s3 in "${a_codec_info[@]}"; do
                  [ -n "$(echo "'$s'" | sed -n '/[^0-9]'"$(fn_regexp "$s3" "sed")"'[^0-9]/Ip')" ] && s_channels="${s2%=*}" && break
                done
              fi
              [ "x$s_channels" != "x$s_channels_default" ] && s_channels=".$s_channels" && break
            done
          fi
        fi
        ;;
    esac
  done

  _s_audio_bitrate="$(echo -e "$s_file_stream_info" | sed -n 's/^[ ]*Stream\ .*Audio.* \([0-9]\+\)\ kb\/s/\1kb\/s/p')"
  [ -n "$_s_audio_bitrate" ] && s_audio_bitrate=".$_s_audio_bitrate"

  s_file_size_bytes="$(stat "$s_file" | sed -n 's/[ ]*Size: \([0-9]\+\).*/\1/p')"
  s_file_size="$(echo "scale=2; $s_file_size_bytes/1024^2" | bc)MB|"

  [[ "x$s_audio" == "x$s_audio_default" && "x$s_video" == "xmpeg2" ]] && s_audio=""
  [ $level -lt 2 ] && s_file_size="" && s_length=""
  [ $level -lt 3 ] && s_size=""
  [ $level -lt 4 ] && s_fps=""
  [ $level -lt 5 ] && s_audio_bitrate="" && s_video_bitrate=""
  [ "x$s_type" = "xaudio" ] && s_size="" && s_fps="" && s_video="" && s_video_bitrate="" && s_audio="${s_audio#.}"
  [ $level -gt 0 ] && echo "$s_file_size$s_length$s_fps$s_size$s_video$s_video_bitrate$s_audio$s_channels$s_audio_bitrate"
}

fn_files_info() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_files_info]" 1>&2

  #echo "#args: $#" 1>&2
  [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/^[0-9]\+$/p')" ]] && level=$1 && shift || level=1
  #echo "#args: $#" 1>&2
  if [ $# -gt 1 ]; then
    s_files=("$@")
  else
    s_search="$1" && shift
    if [ -f "$s_search" ]; then
      s_files=("$s_search")
    elif [ -d "$s_search" ]; then
      s_="$(find "$s_search" -maxdepth 1 -type f -iregex '^.*\.\('"$(echo $VIDEXT\|$AUDEXT | sed 's|\||\\\||g')"'\)$' | sort -i)"
      res=$? && [ $res -ne 0 ] && return $res
      IFS=$'\n'; s_files=($(echo "$s_")); IFS=$IFSORG
    else
      s_="$(fn_search "$s_search")"
      res=$? && [ $res -ne 0 ] && return $res
      IFS=$'\n'; s_files=($(echo "$s_")); IFS=$IFSORG
    fi
  fi
  s_length="00:00:00.00"
  l=0
  for f in "${s_files[@]}"; do
    # allow archive strings through (match '|')
    [ -z "$(echo "$f" | grep -iP "\||(\.($VIDEXT|$AUDEXT)$)")" ] && continue
    #echo -ne "#$f$([ $level -gt 2 ] && echo '\n' || echo ' | ')"
    if [ $level -eq 0 ]; then
      echo "#$f" && fn_file_info $level "$f"
    else
      s=$(fn_file_info $level "$f")
      echo -e "[$s]  \t$f"
      #[ $level -ge 3 ] && s_length=$(fn_position_add "$s_length" "$(echo "$s" | sed -n 's/^\[\(.*\)|.*$/\1/p')" 2>/dev/null)
      [ $level -ge 3 ] && s_length=$(fn_position_add "$s_length" "$(echo "$s" | cut -d'|' -f1)" 2>/dev/null)
    fi
    l=$((l + 1))
  done
  [[ $level -ge 3 && $l -gt 1 ]] && echo "[total duration: $s_length]"
}

fn_file_multi_mask() {
  # determine an appropriate default multifile mask for multi-file
  # titles, and optionally set values
  # passing title: determine type. return default mask
  # passing title and target: get mask from target, search for values
  # in title to set mask. return set mask

  [ $DEBUG -ge 1 ] && echo "[debug fn_file_multi_mask]" 1>&2

  declare -a mask_parts
  declare -a mask_zeros
  declare -a mask_values
  declare v_mask_part
  declare v_mask_zero
  declare v_mask_value
  declare l

  s_title="$1" && shift
  s_target="" && [ $# -gt 0 ] && s_target="$1" && shift
  s_mask_default="" && [ $# -gt 0 ] && s_mask_default="$1" && shift
  s_mask_val=""
  s_mask_default_single="#of#"
  s_mask_default_set="s##e##"

  # determine type
  s_type=""
  if [ -n "$s_target" ]; then
    # look for default mask in target
    # single?
    s_mask="$(echo "$s_target" | sed -n 's|^.*\(#\+of[0-9#]\+\).*$|\1|p')"
    if [ -n "$s_mask" ]; then
      s_type="single" && s_mask_default="${s_mask_default:-$s_mask}"
    else
      #set?
      s_mask="$(echo "$s_target" | sed -n 's|^.*\(s#\+e#\+\).*$|\1|p')"
      if [ -n "$s_mask" ]; then
        s_type="set" && s_mask_default="${s_mask_default:-$s_mask}"
      fi
    fi
  fi

  # filters
  arr=("single #of#"
       "single cd\([0-9]\+\)"
       "single cd[-.]\([0-9]\+\)"
       "single cd\s\([0-9]\+\)"
       "single \([0-9]\+\)of[0-9]\+"
       "single \([0-9]\+\)\.of\.[0-9]\+"
       "set s#\+e#\+"
       "set s\([0-9]\+\)\.\?e\([0-9]\+\)"
       "set \([0-9][0-9]\)x\([0-9]\{1,2\}\)"
       "set \([0-9]\)x\([0-9]\{1,2\}\)"
       "set (\s*\(0*[0-9]\)\.\?\([0-9]\{1,2\}\)\s*)"
       "set \[\s*\(0*[0-9]\)\.\?\([0-9]\{1,2\}\)\s*\]"
       "set \.\s*\(0*[0-9]\)\.\?\([0-9]\{1,2\}\)\s*\."
       "set \-\s*\(0*[0-9]\)\.\?\([0-9]\{1,2\}\)\s*\-"
       "set [.-_]\([0-9]\{2\}\)\-\([0-9]\+\)[._-]"
       "set [.-_]\([0-9]\{1\}\)\-\([0-9]\+\)[._-]"
       "set \-\.\?ep\?\.\?\([0-9]\+\)\.\?\-"
       "set \.ep\?\.\?\([0-9]\+\)\."
       "set \.s\.\?\([0-9]\+\)\. \1\|0"
       "set part\.\?\([0-9]\+\)"
       "set \([0-9]\+\)\.\?of\.\?[0-9]\+ \1|0"
       "single part\.\?\([0-9]\+\)")

       # invalid
       #"single [-.]\([1-4]\)[-.]"  # false positive for name.#.

  l=1
  for s in "${arr[@]}"; do
    [ $DEBUG -ge 5 ] && echo "[debug] filter: [$l] '$s'" 1>&2
    #[ "x$s" = x"set \([0-9]\)x\([0-9]\{1,2\}\)" ] && set -x || set +x
    IFS=" "; arr2=($(echo "$s")); IFS=$IFSORG
    #[[ -n "$s_type" && "x$s_type" != "x${arr2[0]}" ]] && continue
    s_search=${arr2[1]}
    s_replace="" && [ ${#arr2} -ge 2 ] && s_replace=${arr2[2]}
    [[ -z $s_replace && "x${arr2[0]}" == "single" ]] && s_replace="\1"
    [[ -z $s_replace && "x${arr2[0]}" == "set" ]] && s_replace="\1\|\2"
    s_mask_raw=$(echo "${s_title##/}" | sed -n 's|^.*\('"$s_search"'\).*$|\1|Ip')
    if [ -n "$s_mask_raw" ]; then
      s_type="${arr2[0]}"
      s_="s_mask_default_${s_type}" && s_mask_default="${s_mask_default:-"$(eval "echo \$$s_")"}"
      s_mask_val=$(echo "${s_title##/}" | sed -n 's|^.*'"${arr2[1]}"'.*$|'$s_replace'|Ip' 2>/dev/null)
#      case $s_type in
#        "single") s_mask_val=$(echo "${s_title##/}" | sed -n 's|^.*'"${arr2[1]}"'.*$|\1|Ip' 2>/dev/null) ;;
#        "set")
#          s_mask_val=$(echo "${s_title##/}" | sed -n 's|^.*'"${arr2[1]}"'.*$|\1\|\2|Ip' 2>/dev/null)
#          [ -z "$s_mask_val" ] && s_mask_val=$(echo "${s_title##/}" | sed -n 's|^.*'"${arr2[1]}"'.*$|0\|\1|Ip' 2>/dev/null)
#          ;;
#      esac
      break
    fi
    l=$((l + 1))
  done

  s_ret="$s_target" && [ -z "$s_ret" ] && s_ret="$s_mask_default"
  if [ "$s_mask_val" ]; then
    # set mask

    # replacing right to left is impossible to do directly in gnu sed
    # due to its lack of non-greedy matching. this is worked around by
    # collecting mask parts and creating a padded (where necessary)
    # replacement array of the same dimension. then left to right
    # replacement is trivial

    # mask parts / zero stubs
    while [ -n "$(echo "$s_ret" | sed -n '/#\+/p')" ]; do
      # create padded 0-mask
      s_="$(echo "$s_ret" | sed -n 's/^[^#]*\(#\+\).*$/\1/p')"
      mask_parts[${#mask_parts[@]}]="$s_"
      mask_zeros[${#mask_zeros[@]}]="$(printf "%0"${#s_}"d" 0)"
      # set mask marker
      s_ret="$(echo "$s_ret" | sed -n 's/#\+/\^/p')"
    done

    # mask values
    IFS=$'|'; mask_values=($(echo "$s_mask_val")); IFS="$IFSORG"

    # merge available mask values with 0-mask stubs and replace ^
    # markers from left to right
    l=0
    for l in $(seq 0 1 $((${#mask_parts[@]} - 1))); do
      v_mask_part="${mask_parts[$l]}"
      v_mask_zero="${mask_zeros[$l]}"
      v_mask_value=""
      if [ $l -lt ${#mask_values[@]} ]; then
        v_mask_value="${mask_values[$l]}"
        v_mask="$(printf "%0${#v_mask_zero}d" "$(echo "$v_mask_value" | sed 's/^0*//')")"
      else
        v_mask="$v_mask_part"
      fi
      s_ret=$(echo "$s_ret" | sed 's|\^|'$v_mask'|')
      l=$((l + 1))
    done
  fi

  # prefix
  [ -z "$s_target" ] && s_ret="$s_mask_default|$s_mask_raw|$s_ret"

  # return
  echo "$s_ret"
}

fn_file_target() {
  # set a target name for a file. attempt to set mask for
  # multi-file titles. assume no target extention

  [ $DEBUG -ge 1 ] && echo "[debug fn_file_target]" 1>&2

  s_title="$(echo "${1##*/}" | awk -F'\n' '{print tolower($1)}')"
  s_target="$2"
  s_extra="$3"
  s_ext="${s_title##*.}"
  s_target_ext="$s_ext"
  case "$s_target_ext" in
    "txt") s_target_ext="nfo" ;;
    "jpeg") s_target_ext="jpg" ;;
  esac
  if [ -n "$(echo "$s_ext" | grep -iP "^.*($VIDEXT|$VIDXEXT)\$")" ]; then
    # multi-file mask?
    s_target=$(fn_file_multi_mask "$s_title" "$s_target")
    #if [ -n "$s_mask" ]; then
    #  # use dynamic mask
    #  s_mask2=$(echo $s_mask | sed 's|\[#of|\['$n'of|')
    #  s_target=$(echo "$s_target" | sed 's|'$s_mask'|'$s_mask2'|')
    #  s_target="$s_target$s_extra$s_ext"
    #elif [ "${s_title##*.}" != "$s_title" ]; then
    #  # use static mask and file's extension
    #  s_target="$s_target$s_extra$s_ext"
    #fi
    [ "x${s_title##*.}" != "x$s_title" ] && s_target="$s_target.$s_extra.$s_ext"
  elif [ "x${s_title##*.}" != "x$s_title" ]; then
    # use static mask and file's extension
    s_target="$s_target.$s_target_ext"
  else
    # default
    s_target=
  fi
  [ $DEBUG -ge 1 ] && echo "[debug fn_file_target] s_target: '$s_target'" 1>&2
  echo "$s_target" | sed 's/\(^\.\|\.$\)//g'
}

fn_files() {
  # given a file name, return a tab delimited array of associated
  # files in the local directory

  [ $DEBUG -ge 1 ] && echo "[debug fn_files]" 1>&2

  b_verbose=1
  [ "x$1" = "xsilent" ] && b_verbose=0 && shift
  b_interactive=0
  [ "x$1" = "xinteractive" ] && b_interactive=1 && shift
  l_depth=1
  [ "x$1" = "xfull" ] && l_depth=10 && shift
  s_search="$1" && shift
  s_search_prev=""
  s_search_last=""
  s_search_custom=""
  l_found=0
  l_found_prev=0
  l_found_first=0 # used to delay exit to 2nd successful search
  l_found_last=0
  b_auto=1
  b_merge=0
  b_search=1
  s_type=""
  [ $# -gt 0 ] && s_type="$1" && shift

  while [ $b_search -gt 0 ]; do
    b_searched=0
    b_diff=0
    if [[ $b_interactive -eq 0 && (
            ${#s_search} -eq 0 ||
            (${#s_search} -le $MINSEARCH && $l_found_last -gt $l_found_first)) ]]; then
      b_search=0
    else
      if [[ $b_auto -eq 0 ||
           ($b_auto -eq 1 && ${#s_search} -ge $MINSEARCH) ||
           ($b_auto -eq 1 && $b_interactive -eq 1) ]]; then
           #($b_auto -eq 1 && ${#s_search} -ge $MINSEARCH) ]]; then
        # whenever there is a difference between the new search and the
        # previous search replace the last search by the previous search
        [ $DEBUG -ge 2 ] && echo "[debug fn_files] #1 s_search: '$s_search' s_search_custom: '$s_search_custom' s_search_prev: '$s_search_prev'  s_search_last: '$s_search_last'" 1>&2
        [ -n "$s_search_custom" ] && s_search_prev="$s_search" && s_search="$s_search_custom"
        if [[ "x$s_search" != x$s_search_prev || -z "$s_search_last" ]]; then
          s_="$(find ./ -maxdepth $l_depth -iregex '.*'"$(fn_regexp "$s_search" "sed")"'.*\('"$(fn_regexp "$s_type" "sed")"'\)$' | sort -i)"
          res=$? && [ $res -ne 0 ] && return $res
          IFS=$'\n'; s_files=($(echo "$s_")); IFS=$IFSORG

          s_files2=()
          for s_ in "${s_files[@]}"; do
            if [ -d "$s_" ]; then
              s__="$(find "$s_/" $s_depth -type f | sort -i)"
              res=$? && [ $res -ne 0 ] && return $res
              IFS=$'\n'; s_files2=("${s_files2[@]}" $(echo "$s__")); IFS="$IFSORG"
            else
              s_files2=("${s_files2[@]}" "$s_")
            fi
          done
          s_files=("${s_files2[@]}")
          l_found=${#s_files[@]}
          if [ $l_found -ne $l_found_prev ]; then
            b_diff=1
          elif [ $b_auto -eq 0 ]; then
            # compare old and new searches
            declare -A arr
            for f in "${s_files_prev[@]}"; do arr["$f"]="$f"; done
            for f in "${s_files[@]}"; do [ -z "${arr[$f]}" ] && b_diff=1 && break; done
          fi
          if [ $b_diff -eq 1 ]; then
            # keep record for revert
            l_found_last=$l_found_prev
            s_files_last=(${s_files_prev[@]})
            s_search_last=$s_search_prev
            [ $DEBUG -ge 2 ] && echo "[debug fn_files] l_found_last: '$l_found_last', s_search_last: '$s_search_last', s_files_last: '${s_files_last[@]}'" 1>&2
          fi
          if [ $l_found_first -eq 0 ]; then l_found_first=$l_found; fi
          if [ $b_merge -eq 1 ]; then
            [ $DEBUG -ge 2 ] && echo "[debug fn_files] l_found_last: '$l_found_last', s_search_last: '$s_search_last', s_files_last: '${s_files_last[@]}'" 1>&2
            s_files2=("${s_files[@]}") && s_files=("${s_files_last[@]}")
            declare -A arr
            for f in "${s_files_last[@]}"; do arr["$f"]="$f"; done
            for f in "${s_files2[@]}"; do [ -z "${arr[$f]}" ] &&
                                         s_files=("${s_files[@]}" "$f"); done
            l_found=${#s_files[@]}
          fi
        fi
      fi
      [ $DEBUG -ge 2 ] && echo "[debug fn_files] #2 s_search: '$s_search' s_search_custom: '$s_search_custom' s_search_prev: '$s_search_prev'  s_search_last: '$s_search_last'" 1>&2
      if [[ ($b_diff -eq 1) ||
            ($b_interactive -eq 1 && $b_auto -eq 0) ||
            ($b_auto -eq 1 && ${#s_search} -le $MINSEARCH) ]]; then
        [ $DEBUG -ge 1 ] && echo "[debug fn_files] $s_search == $s_search_prev ??" 1>&2
        if [ $b_verbose -eq 1 ]; then
          if [[ $b_auto -eq 1 && $b_diff -eq 0 && ${#s_search} -le $MINSEARCH && x$s_search == x$s_search_prev ]]; then
            echo "minimum search term length hit with '$s_search'" 1>&2
          else
            echo -e "found ${#s_files[@]} associated files searching with '$s_search'" 1>&2
          fi
        fi
        if [ $b_interactive -gt 0 ]; then
          l=0; for f in "${s_files[@]}"; do l=$((l + 1)); echo "  $f" 1>&2; [ $l -ge 10 ] && break; done
          if [ $l_found -gt 10 ]; then echo "..." 1>&2; fi
          echo -ne "search for more files automatically [y]es/[n]o" \
            "or manually [a]ppend/[c]lear? [r]evert matches or e[x]it? " 1>&2
          b_retry=1
          while [ $b_retry -gt 0 ]; do
            result=
            read -s -n 1 result
            case "$result" in
              "y"|"Y") echo "$result" 1>&2; b_retry=0; b_auto=1; s_search_custom="" ;;
              "n"|"N") echo "$result" 1>&2; b_retry=0; b_search=0 ;;
              "a"|"A") echo "$result" 1>&2; b_retry=0; b_auto=0; b_merge=1; echo -n "search: " 1>&2; read s_search_custom ;;
              "c"|"C") echo "$result" 1>&2; b_retry=0; b_auto=0; echo -n "search: " 1>&2; read s_search_custom ;;
              "r"|"R") echo "$result" 1>&2; b_retry=0; b_auto=0; b_merge=0; s_search_custom="$s_search_last" ;;
              "x"|"X") echo "$result" 1>&2; return 1 ;;
            esac
          done
        else
          if [[ (-n "$s_search_last" && $l_found -gt 1) || ${#s_search} -le $MINSEARCH ]]; then b_search=0; fi
        fi
      else
        if [[ $b_auto -eq 1 && ${#s_search} -le $MINSEARCH ]]; then
          if [ $b_interactive -eq 0 ]; then b_search=0; fi
        fi
      fi
      s_search_prev="$s_search"
      s_files_prev=("${s_files[@]}")
      l_found_prev=$l_found
      if [[ $b_auto -eq 1 && ${#s_search} -gt $MINSEARCH ]]; then  s_search=${s_search:0:$((${#s_search} - 1))}; fi
      [ $DEBUG -ge 2 ] && echo "[debug fn_files] #3 s_search: '$s_search' s_search_custom: '$s_search_custom' s_search_prev: '$s_search_prev'  s_search_last: '$s_search_last'" 1>&2
    fi
  done

  # verify files
  [ $DEBUG -ge 1 ] && echo "[debug fn_files] s_files: '${s_files[@]}'" 1>&2
  b_verify=1
  if [ $l_found -gt 0 ]; then
    if [ $b_interactive -eq 0 ]; then
      s_files2=("${s_files[@]}")
    else
      echo -e "verify associations for matched files" 1>&2
      b_auto_add=0
      s_files2=()
      for s_ in "${s_files[@]}"; do
        if [ -d "$s_" ]; then
          s__="$(find "$s_" -type f | sort -i)"
          res=$? && [ $res -ne 0 ] && return $res
          IFS=$'\n'; s_files3=($(echo "$s_")); IFS="$IFSORG"
          for s__ in "${s_files3[@]}"; do
            b_add=0
            if [ $b_auto_add -gt 0 ]; then
              b_add=1
            else
              echo -ne "  $s__ [(y)es/(n)o/(a)ll/(c)ancel/e(x)it] " 1>&2
              b_retry=1
              while [ $b_retry -gt 0 ]; do
                result=
                read -s -n 1 result
                case "$result" in
                  "y"|"Y") echo "$result" 1>&2; b_retry=0; b_add=1 ;;
                  "n"|"N") echo "$result" 1>&2; b_retry=0 ;;
                  "a"|"A") echo "$result" 1>&2; b_retry=0; b_add=1; b_auto_add=1 ;;
                  "c"|"C") echo "$result" 1>&2; b_retry=0; b_verify=0 ;;
                  "x"|"X") echo "$result" 1>&2; return 1 ;;
                esac
              done
            fi
            if [ $b_add -eq 1 ]; then s_files2=("${s_files2[@]}" "$s__"); fi
            if [ $b_verify -eq 0 ]; then break; fi
          done
        elif [ -f "$s_" ]; then
          b_add=0
          if [ $b_auto_add -gt 0 ]; then
            b_add=1
          else
            echo -ne "  $s_ [(y)es/(n)o/(a)ll/(c)ancel/e(x)it] " 1>&2
            b_retry=1
            while [ $b_retry -gt 0 ]; do
              result=
              read -s -n 1 result
              case "$result" in
                "y"|"Y") echo "$result" 1>&2; b_retry=0; b_add=1 ;;
                "n"|"N") echo "$result" 1>&2; b_retry=0 ;;
                "a"|"A") echo "$result" 1>&2; b_retry=0; b_add=1; b_auto_add=1 ;;
                "c"|"C") echo "$result" 1>&2; b_retry=0; b_verify=0 ;;
                "x"|"X") echo "$result" 1>&2; return 1 ;;
              esac
            done
          fi
          if [ $b_add -eq 1 ]; then s_files2=("${s_files2[@]}" "$s_"); fi
          if [ $b_verify -eq 0 ]; then break; fi
        fi
      done
    fi
  fi
  IFS=$IFSORG

  [ $DEBUG -ge 1 ] && echo "[debug fn_files] s_files2: '${s_files2[@]}'" 1>&2
  if [[ -n "${s_files2}" && ${#s_files2[@]} -gt 0 ]]; then
    [ $b_verbose -eq 1 ] && fn_log "associated files for '$s_search': '${s_files2[@]}'"
    #return '\n' delimited strings
    for f in "${s_files2[@]}"; do echo "$f"; done
  fi
}

fn_search() {

  [ $DEBUG -ge 1 ] && echo "[debug fn_search]" 1>&2

  declare -a targets
  declare target
  declare search_type
  declare search
  declare -a args
  declare l
  declare l_s
  declare f

  declare substring_search; substring_search=0
  declare interactive; interactive=0
  declare extensions; extensions="$VIDEXT|$AUDEXT"

  # process args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
    case "$arg" in
      "ss"|"substring-search") shift; substring_search=1 ;;
      "i"|"interactive") shift; interactive=1 ;;
      "x"|"extensions") shift; extensions="$1"; shift ;;
      *)
        [ -z "$search" ] && \
          { search="$1"; shift; } || \
          { help; echo "[error] unsupported arg '$1'" 1>&2; return 1; }
    esac
  done

  # validate args
  [ -z "$search" ] && help && echo "[error] missing 'search' arg" 1>&2 && return 1
  l_s=${#search}

  [ $DEBUG -ge 1 ] && echo "[debug fn_search] pre-processing search: '$search'" 1>&2
  if [ $regexp -eq 1 ]; then
    search_type="regexp"
  else
    # search is glob or raw / literal string
    # find special chars
    l=0
    while [[ $l -lt $l_s && $l -lt $l_s ]]; do
      char="${search:$l:1}"
      case "$char" in
        '\') l=$((l + 1)) ;;
        '*') ;;
        '['|']'|'('|')'|'+'|'^'|'$'|'{'|'}') search_type="raw"; break ;;
      esac
      l=$((l + 1))
    done
    search_type="${search_type:-"glob"}"
  fi
  # path escapes
  for c in \' ' ' \"; do
    search=${search//"$c"/"\\$c"}
  done
  [ $DEBUG -ge 1 ] && echo "[debug fn_search] post-processing search: '$search', search type: '$search_type'" 1>&2

  targets=("$(pwd)")
  if [ -n "$PATHMEDIATARGETS" ]; then
    IFS="|"; a_=($(echo "$PATHMEDIATARGETS")); IFS="$IFSORG"
    for s_ in "${a_[@]}"; do
      [ -d "$s_" ] && \
        targets[${#targets[@]}]="$s_" || \
        targets[${#targets[@]}]="$PATHMEDIA/$s_"
    done
  else
    targets[${#targets[@]}]="$PATHMEDIA"
  fi

  IFS=$'\n'
  b_continue=1
  while [ $b_continue -eq 1 ]; do
    for target in "${targets[@]}"; do
      [ $DEBUG -ge 1 ] && echo "[debug fn_search] search: '$search', target: '$target'" 1>&2
      case "$search_type" in
        "regexp")
          # search as valid regular expression
          arr=($(find $target -type f -name "*" | grep -iP ".*$search.*" | grep -iP '('"$extensions"')$' | sort -i 2>/dev/null))
          ;;
        "raw")
          # search as raw string
          arr=($(find $target -type f -name "*" | grep -iP ".*$(fn_regexp "$search" "perl").*($extensions)" | sort -i 2>/dev/null))
          ;;
        "glob")
          # search as a glob
          arr=($(find $target -type f -iname "*$search*" | grep -iP '('"$extensions"')$' | sort -i 2>/dev/null))
          ;;
      esac

      if [[ ${#arr[@]} -gt 0 && -n "$arr" ]]; then
        b_add=1
        if [ $interactive -eq 1 ]; then
          echo "[user] target: '$target', search: '*search*', found files:" 1>&2
          for f in "${arr[@]}"; do echo "  $f" 1>&2; done
          echo -n "[user] search further? [(y)es/(n)o/e(x)it]:  " 1>&2
          b_retry2=1
          while [ $b_retry2 -eq 1 ]; do
            echo -en '\033[1D\033[K'
            read -n 1 -s result
            case "$result" in
              "x" | "X") echo -n $result; b_retry2=0; b_continue=0; echo ""; return 0 ;;
              "n" | "N") echo -n $result; b_retry2=0; b_retry=0; b_continue=0; echo ""; break ;;
              "y" | "Y") echo -n $result; b_retry2=0; b_add=0 ;;
              *) echo -n " " 1>&2
            esac
          done
          echo ""
        fi
        if [ $b_add -eq 1 ]; then
          [[ ${#files[@]} -gt 0 && -n "$files" ]] && files=("${files[@]}" "${arr[@]}") || files=("${arr[@]}")
        fi
      fi
    done
    if [ -d "$PATHARCHIVELISTS" ]; then
      case "$search_type" in
        "regexp")
          arr=($(grep -riP "$search" "$PATHARCHIVELISTS" 2>/dev/null))
          ;;
        "raw")
          arr=($(grep -riP "$(fn_regexp "$search" "perl")" "$PATHARCHIVELISTS" 2>/dev/null))
          ;;
        "glob")
          arr=($(grep -rie "$search" "$PATHARCHIVELISTS" 2>/dev/null))
          ;;
      esac
      [ $DEBUG -ge 1 ] && echo "[debug fn_search] results arr: '${arr[@]}'" 1>&2
      # format archive results 'file|info'
      if [[ ${#arr[@]} -gt 0 && -n "$arr" ]]; then
        arr_2=()
        for s_ in ${arr[@]}; do
          s__="$(echo "$s_" | sed -n 's/^\([^:~]*\):\([^|]*\).*$/\1|\2/p')"
          [ -z "$s__" ] && echo "[info] invalid archive format: '$s_'" && continue
          f="${s__%|.*}"
          case "$search_type" in
            "regexp")
              f="$(echo "$f" | grep -iP "$search" 2>/dev/null)"
              ;;
            "raw")
              f="$(echo "$f" | grep -iP "$(fn_regexp "$search" "perl")" 2>/dev/null)"
              ;;
            "glob")
              f="$(echo "$f" | grep -ie "$search" 2>/dev/null)"
              ;;
          esac
          [ -z "$f" ] && continue  # false positive
          arr_2[${#arr_2[@]}]="$s__"
        done
        [ $DEBUG -ge 1 ] && echo "[debug fn_search] filtered results arr2: '${arr2[@]}'" 1>&2
        # merge results
        b_add=1
        if [ $interactive -eq 1 ]; then
          echo "[user] target: '$target', search: '*search*', found files:" 1>&2
          for f in "${arr[@]}"; do echo "  $f" 1>&2; done
          echo -n "[user] search further? [(y)es/(n)o/e(x)it]:  " 1>&2
          b_retry2=1
          while [ $b_retry2 -eq 1 ]; do
            echo -en '\033[1D\033[K'
            read -n 1 -s result
            case "$result" in
              "x" | "X") echo -n $result; b_retry2=0; b_continue=0; echo ""; return 0 ;;
              "n" | "N") echo -n $result; b_retry2=0; b_retry=0; b_continue=0; echo ""; break ;;
              "y" | "Y") echo -n $result; b_retry2=0; b_add=0 ;;
              *) echo -n " " 1>&2
            esac
          done
          echo ""
        fi
        if [ $b_add -eq 1 ]; then
          [[ ${#files[@]} -gt 0 && -n "$files" ]] && files=(${files[@]} ${arr2[@]}) || files=(${arr2[@]})
        fi
      fi
    else
      [ $DEBUG -ge 1 ] && echo "[debug] no archive lists found at: '$PATHARCHIVELISTS'" 1>&2
    fi

    if [[ $substring_search -eq 0 || \
          ${#search} -le $MINSEARCH || \
          (${#files[@]} -gt 0 && -n "${files}") ]]; then
      b_continue=0
    else
      # trim token ('][)(.,:- ' delimiter) until too short
      s=$(echo "$search" | sed -n 's/^\(.*\)[][)(.,: -]\+.*$/\1/p')
      [ "${#s}" -lt $MINSEARCH ] && s=${search:0:$((${#search} - 2))}
      [ "${#s}" -lt $MINSEARCH ] && s=${search:0:$((${#search} - 1))}
      search="$s"
      echo "$search" >> /tmp/search
    fi

  done

  # process list
  [ $DEBUG -ge 1 ] && echo "[debug fn_search] processing list: ${files[@]}" 1>&2
  if [[ ${#files[@]} -gt 0 && -n "$files" ]]; then
    printf '%s\n' "${files[@]}" | sort -i
  fi
  IFS=$IFSORG
}

fn_play_list() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_play_list]" 1>&2

  list="$1" && shift
  [ ! -e $list ] && echo "[error] no playlist argument!" && return 1

  IFS=$'\n' items=($(cat $list)); IFS=$IFSORG

  current=${items[0]};
  if [ -e $list.current ]; then
    current="$(cat $list.current)"
  fi

  idx=0
  for li in "${items[@]}"; do
    [ "x$li" = "x$current" ] && break;
    idx=$((idx + 1))
  done

  # select from here

  file="$current"

  if [[ ${#file} -gt 0 && -f "$file" ]]; then
    path="${file%/*}/"
    result=
    b_retry=1
    echo -en '\033[2K\012\033[2K\012\033[2K\012\033[2K\012\033[2K\033[A\033[A\033[A\033[A\033[s\033[B'
    while [ $b_retry -gt 0 ]; do
      echo -en '\033[u\033[s\033[2K\012\033[2K\012\033[2K\012\033[2K\033[u\033[s\012'
      echo -n "play '$file'? [(y)es/(n)o/(u)p/(d)own] "
      read -n 1 -s c1
      read -sN1 -t 0.0001 c2
      read -sN1 -t 0.0001 c3
      read -sN1 -t 0.0001 c4
      result=$c1$c2$c3$c4
      case "$result" in

        "u"|$'\e[A') [ ${#items[@]} -gt $idx ] && idx=$((idx + 1)) && file="${items[$idx]}" ;;

        "d"|$'\e[B') [ $idx -gt 0 ] && idx=$((idx - 1)) && file="${items[$idx]}" ;;

        "n"|"N") echo $result; b_retry=0 ;;

        "y"|"Y")
          echo $result
          # write current
          echo "$file" > "$list".current
          # create playlist from remaining items
          last=$((${#items[@]} - idx))
          tail -n $last $list > $PLAYLIST
          # play list
          $cmdplay $cmdplay_options $cmdplay_playlist_options$PLAYLIST $@
          b_retry=0
          ;;

        *)
          echo "result: $result"
          ;;

      esac
    done
  fi
}

fn_play() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_play]" 1>&2

  declare s_search

  # process args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
    case "$arg" in
      *)
        [ -z "$s_search" ] && \
          { s_search="$1"; shift; } || \
          { help; echo "[error] unsupported arg '$1'" 1>&2; return 1; }
    esac
  done

  declare -a search_args
  search_args[${#search_args[@]}]="$s_search"

  display=$(fn_display)
  [ $DEBUG -ge 1 ] && echo "[debug fn_play] display: '$display', search: '$s_search'" 1>&2

  [[ -d "$s_search" || -f "$s_search" ]] && DISPLAY=$display $CMDPLAY $CMDPLAY_OPTIONS "$s_search" "$@" && return 0
  s_=$(fn_search "${search_args[@]}")
  res=$? && [ $res -ne 0 ] && return $res
  IFS=$'\n'; s_matched=(echo "$s_"); IFS=$IFSORG

  play=0
  cmdplay="$([ $DEBUG -ge 1 ] && echo 'echo ')$CMDPLAY"
  cmdplay_options="$CMDPLAY_OPTIONS"
  cmdplay_playlist_options="$CMDPLAY_PLAYLIST_OPTIONS"

  echo supported file-types: $VIDEXT 1>&2
  #VIDEXT="($(echo $VIDEXT | sed 's|\||\\\||g'))"

  if [[ ${#s_matched[@]} -gt 0 && -n "$s_matched" ]]; then
    # files to play!
    # iterate results. prepend titles potentially requiring user
    # interation (e.g. using discs)
    # format | type:name[:info] -> title:file[:search]
    [ $DEBUG -eq 2 ] && echo "[debug fn_play] s_matched: ${s_matched[@]}"
    s_playlist=
    for s in "${s_matched[@]}"; do
      [ -z "$(echo "$s" | grep '|')" ] && s="file|$s"
      type="${s%%|*}" && s=${s:$((${#type} + 1))} && type="${type##*/}"
      name="${s%%|*}" && s=${s:$((${#name} + 1))}
      s=""
      prepend=0
      #title="$(echo "$name" | sed -n 's/^.*\/\([^[]*\)[. ]\+.*$/\1/p')"
      title="${name##*/}" && title="${title%[*}" && title="$(echo "$title" | sed 's/\(^\.\|\.$\)//g')"  # alternative approach below
      case "$type" in
        "dvd"|"dvds") s="$title|dvdnav:////dev/dvd"; prepend=1 ;;
        "vcd"|"vcds") s="$title|vcd:////dev/dvd"; prepend=1 ;;
        "cd"|"cds") s="$title|/dev/dvd|$s_search"; prepend=1 ;;
        "file"|"files") s="$title|$name" ;;
        *) s="$title|$ROOTDISK$type/$name" ;; #convert archive entry to location
      esac
      # add to list
      if [ -z "${s_playlist}" ]; then
        s_playlist=("$s")
      else
        [ $prepend -eq 1 ] && s_playlist=("$s" "${s_playlist[@]}") || s_playlist=("${s_playlist[@]}" "$s")
      fi
    done

    # iterate list and play
    # format | title:file[:search]
    [ $DEBUG -eq 2 ] && echo "[debug fn_play] s_playlist: ${s_playlist[@]}" 1>&2
    s_files=
    for s in "${s_playlist[@]}"; do
      title="${s%%|*}" && s=${s:$((${#title} + 1))} && title="$(echo ${title##*/} | sed 's/[. ]\[.*$//I')"
      file="${s%%|*}" && s=${s:$((${#file} + 1))}
      search="$s" && [ "x$search" = "x$file" ] && search=""
      [ $DEBUG -ge 1 ] && echo "[debug fn_play] title: '$title', file: '$file', search: '$search'" 1>&2
      if [ -n "$(echo "$file" | grep "/dev/dvd")" ]; then
        # play?
        echo -n "play '$title'? [(y)es/(n)o/e(x)it]:  "
        b_retry=1
        while [ $b_retry -eq 1 ]; do
          echo -en '\033[1D\033[K'
          read -n 1 -s result
          case "$result" in
            "x" | "X") echo -n $result; b_retry=0; echo ""; return 0 ;;
            "n" | "N") echo -n $result; b_retry=0; file="" ;;
            "y" | "Y") echo -n $result; b_retry=0 ;;
            *) echo -n " " 1>&2
          esac
        done
        echo ""
        if [ -n "$file" ]; then
          played=0
          b_retry=1
          s_files=
          while [ $b_retry -eq 1 ]; do
            [ $played -gt 0 ] && NEXT="next "
            if [ "${#s_files}" -gt 0 ]; then
              # files to play
              if [ "x$file" = "x/dev/dvd" ]; then
                type="cd" # cds
                echo "playing '$title' [cd]" 1>&2
                for f in "${s_files[@]}"; do DISPLAY=$display $cmdplay $cmdplay_options $@ "$ROOTISO$f"; done
                umount "$ROOTISO" 2>/dev/null
              else
                type="${file:0:3}" # dvds/vcds
                echo "playing '$title' []" 1>&2
                DISPLAY=$display $cmdplay $@ $cmdplay_options "${s_files[0]}"
              fi
              played=$((played + ${#s_files[@]}))
              s_files=
            else
              if [[ ! -t $(fn_drive_status) || $played -gt 0 ]]; then
                # block until disc is inserted
                echo -n "[user] insert "$NEXT"disk for '$title' [(r)etry|(e)ject|(l)oad|e(x)it]:  "
                b_retry2=1
                while [ $b_retry2 -eq 1 ]; do
                  echo -en '\033[1D\033[K'
                  read -n 1 -s result
                  case "$result" in
                    "r" | "R") echo -n $result; [ -t $(fn_drive_status) ] && b_retry2=0 ;;
                    "e" | "E") echo -n $result; umount /dev/dvd >/dev/null 1>&2; [ -t $(fn_drive_status) ] && eject -T >/dev/null 1>&2 ;;
                    "l" | "L") echo -n $result; [ ! -t $(fn_drive_status) ] && eject -t 2>/dev/null ;;
                    "x" | "X") echo -n $result; b_retry=0; b_retry2=0; file="" ;;
                    *) echo -n " " 1>&2
                  esac
                done
                echo ""
              fi
              if [ -n "$file" ]; then
                if [ "x$file" = "x/dev/dvd" ]; then
                  # mount and search for files
                  mount -t auto -o ro /dev/dvd "$ROOTISO" 2>/dev/null && sleep 1
                  cd $ROOTISO
                  IFS=$'\n'
                  s_files=($(fn_files silent full "$search" "$VIDEXT"))
                  x=$?
                  if [ ${#s_files[@]} -eq 0 ]; then
                    s_files=($(fn_files interactive full "$search" "$VIDEXT"))
                    x=$?
                  fi
                  IFS=$IFSORG
                  cd - >/dev/null 2>&1
                  [ $x -ne 0 ] && b_retry=0 && s_files= && continue
                else
                  # specify the track for vcds
                  if [ "x${file:0:3}" = "xvcd" ]; then
                    #ID_VCD_TRACK_1_MSF=00:16:63
                    IFS=$'\n'; s_tracks=($($CMDINFOMPLAYER "$file" | sed -n 's/^ID_VCD_TRACK_\([0-9]\)_MSF=\([0-9:]*\)$/\1|\2\.0/p')); IFS=$IFSORG
                    if [ ${#s_tracks[@]} -gt 0 ]; then
                      for s in "${s_tracks[@]}"; do
                        s_track_time2=$(fn_position_time_to_numeric "${s##*|}")
                        if [[ -z "$s_track" || $(math_ "\$gt($s_track_time2, $s_track_time)") -eq 1 ]]; then
                          s_track="${s%%|*}"
                          s_track_time="$s_track_time2"
                        fi
                      done
                    fi
                    [ -z "$s_track" ] && s_track="1"
                    s_files=("$(echo "$file" | sed 's|vcd://|vcd://'$s_track'|')")
                  else
                    s_files=("$file")
                  fi
                fi
              fi
            fi
          done
        fi
      else
        # file type?
        if [ -n "$(echo "$file" | grep -iP '^.*\.('$VIDEXT')$')" ]; then

          # play?
          echo -n "play '$title'? [(y)es/(n)o/(v)erbose/e(x)it]:  "
          b_retry=1
          while [ $b_retry -eq 1 ]; do
            echo -en '\033[1D\033[K'
            read -n 1 -s result
            case "$result" in
              "y" | "Y") echo -n $result; b_retry=0 ;;
              "n" | "N") echo -n $result; b_retry=0; file="" ;;
              "v" | "V") echo -n $result; echo -en "\033[G\033[1Kplay '$file'? [(y)es/(n)o/(v)erbose/e(x)it]:  " ;;
              "x" | "X") echo -n $result; b_retry=0; echo ""; return 0 ;;
              *) echo -n " " 1>&2
            esac
          done
          echo ""

          if [ -n "$file" ]; then
            # block whilst file doesn't exist
            b_retry=1
            while [ $b_retry -eq 1 ]; do
              if [ -e "$file" ]; then
                b_retry=0
              else
                echo -n "[user] file '$file' does not exist? [(r)etry/(s)kip/e(x)it]:  "
                b_retry2=1
                while [ $b_retry2 -eq 1 ]; do
                  echo -en '\033[1D\033[K'
                  read -n 1 -s result
                  case "$result" in
                    "x" | "X") echo -n $result; b_retry=0; b_retry2=0; echo ""; return 0 ;;
                    "s" | "S") echo -n $result; b_retry=0; b_retry2=0 ;;
                    "r" | "R") echo -n $result; b_retry2=0 ;;
                    *) echo -n " " 1>&2
                  esac
                done
                echo ""
              fi
            done
            # add to playlist
            [ $DEBUG -ge 1 ] && echo "[debug fn_play] file: $file" 1>&2
            if [[ -e "$file" && -n "$file" ]]; then
              [ -z "${s_files[@]}" ] && s_files=("$file") || s_files=("${s_files[@]}" "$file")
            fi
          fi
        fi
      fi
    done

    # play remaining files
    if [ -n "${s_files}" ]; then
      [ $DEBUG -ge 1 ] && echo "[debug fn_play] s_files: ${s_files[@]}" 1>&2
      for l in $(seq 0 1 $((${#s_files[@]} - 1))); do
        file="${s_files[$l]}"
        # construct playlist?
        if [ -n "$PLAYLIST" ]; then
          [ $l -eq 0 ] && echo "$file" > "$PLAYLIST" || echo "$file" >> "$PLAYLIST"
        else
          DISPLAY=$display $cmdplay $([ -n "$cmdplay_options" ] && echo "$cmdplay_options") "$file" "$@"
        fi
      done
      [ -n "$PLAYLIST" ] && DISPLAY=$display eval $cmdplay $([ "x$cmdplay_options" != x ] && echo "$cmdplay_options") $([ -n "$cmdplay_playlist_options" ] && echo "${cmdplay_playlist_options}${PLAYLIST}" || echo "$PLAYLIST") "$@"
    fi
  fi
}

fn_archive() {
  # list files at target for archive purposes

  [ $DEBUG -ge 1 ] && echo "[debug fn_archive]" 1>&2

  CWD="$PWD/"
  target="$PATHARCHIVELISTS"
  level=0
  [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/^[0-9]\+$/p')" ]] && level=$1 && shift
  [ $# -gt 0 ] && source="$1" && shift || source="."
  [ -d "$source" ] && cd "$source"
  [ "x${source:$((${#source} - 1)):1}" = "x/" ] && source="${source:0:$((${#source} - 2))}" && shift || source="$PWD"
  [ $# -gt 0 ] && file="$1" && shift || file="${source##*/}"

  source="$source/"
  if [ $level -eq 0 ]; then
    find . -type f -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)' | sort -i > "$target$file"
  else
    IFS=$'\n'; s_files=($(find . -type f -iregex '^.*\.\('"$(echo $VIDEXT | sed 's|\||\\\||g')"'\)' | sort -i)); IFS=$IFSORG
    b_append=0
    for f in "${s_files[@]}"; do
      s="$f|$(fn_file_info $level "$f")"
      if [ $b_append -eq 0 ]; then
        echo "$s" > "$target$file" && b_append=1
      else
        echo "$s" >> "$target$file"
      fi
    done
  fi
  echo "updated archive list: '$target$file'"
  cd $CWD
}

fn_filter() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_filter]" 1>&2

  declare target
  declare target_
  declare options
  declare options_default; options_default="g"
  declare match_case
  declare match_case_default; match_case_default=0
  declare repeat
  declare repeat_default; repeat_default=0
  declare filter
  declare l

  target="$1" && shift

  # process option filter sets
  match_case=$match_case_default
  options="$options_default"
  repeat=$repeat_default
  l=1
  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      "-r"|"--repeat") repeat=1 ;;
      "-mc"|"--match_case") match_case=1 ;;
      *)
        if [ -n "$arg" ]; then
          [ $match_case -eq 0 ] && options+="I"
          filter="$arg"
          target_="$target"
          target="$(echo "$target" | sed 's/'"$filter"'/'"$options")"
          if [ $repeat -eq 1 ]; then
            s_="$(echo "$target" | sed 's/'"$filter"'/'"$options")"
            while [ "x$s_" != "x$target" ]; do
              target="$s_"; s_="$(echo "$target" | sed 's/'"$filter"'/'"$options")"
            done
          fi
          [ $DEBUG -ge 5 ] && echo "[debug] filter #$l: '$filter' applied, '$target_' -> '$target'" 1>&2
        fi
        # reset
        match_case=$match_case_default
        options="$options_default"
        repeat=$repeat_default
        l=$((l + 1))
        ;;
    esac
    shift
  done
  echo "$target"
}

fn_structure() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_structure]" 1>&2

  declare cmdmv; cmdmv="$([ $TEST -ge 1 ] && echo 'echo ')$CMDMV"
  declare cmdmd; cmdmd="$([ $TEST -ge 1 ] && echo 'echo ')$CMDMD"

  declare filters_rc; filters_rc="$FILTERS_EXTRA"
  declare filters_mod; filters_mod='\(\s\|\.\|\[\)*[^(]\([0-9]\{4\}\)\(\s\|\.\|\]\)*/.(\2).'
  declare filters_codecs; filters_codecs="\($(echo "$VIDCODECS|$AUDCODECS" | sed 's/[,=|]/\\\|/g')\)/."
  declare filters_misc; filters_misc='_/\.'
  declare filters_misc2; filters_misc2='\.\-\./\.'
  declare filters_misc3; filters_misc3='\([^.]\)-/\1'
  declare filters_misc4; filters_misc4='-\([^.]\)/\1'
  declare filters_repeat_misc; filters_repeat_misc='\(\[\.*\]\|^\.\|[-.]$\)/'
  declare filters_repeat_misc2; filters_repeat_misc2='\.\./.'

  declare delimiters; delimiters='._-'

  declare filters_cmd; filters_cmd=""
  declare verbose; verbose=1
  declare s_search

  # process args
  while [ -n "$1" ]; do
    arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
    case "$arg" in
      "-s"|"--silent") verbose=0 ;;
      *) [ -z "$s_search" ] && s_search="$1" || filters_cmd="$filters_cmd"'\|'"$1"
    esac
    shift
  done

  # validate args
  [ -z "$s_search" ] && help && echo "[error] missing 'search' arg" 1>&2 && return 1
  [ -n "$filters_cmd" ] && filters_cmd='['"$delimiters"']\+\('"${filters_cmd:2}"'\)\(['"$delimiters"']\|$\)\+/..'

  IFS=$'\n'
  s_files=($(fn_files interactive "$s_search"))
  x=$? && [ $x -ne 0 ] && return $x
  IFS=$IFSORG
  [ ${#s_files} -eq 0 ] && return 1
  [ $DEBUG -ge 1 ] && echo "s_files: '${s_files[@]}'" 1>&2
  # count type files
  # set type template file
  # set title
  l=0
  s_title_template=""
  # set video template file
  for f in "${s_files[@]}"; do
    if [ -n "$(echo "$f" | grep -iP ".*\.($VIDEXT)\$")" ]; then
      [ $l -eq 0 ] && s_title_template="$f"
      l=$((l + 1))
    fi
  done
  l_files=$l
  if [ $l_files -lt 1 ]; then
    # set audio template file
    l=0
    for f in "${s_files[@]}"; do
      if [ -n "$(echo "$f" | grep -iP ".*\.($AUDEXT)\$")" ]; then
        [ $l -eq 0 ] && s_title_template="$f"
        l=$((l + 1))
      fi
    done
    l_files=$l
  fi

  [ $l_files -lt 1 ] && echo "[error] no recognised video or audio extention for any of the selected files" 2>&1 && return 1
  # *IMPLEMENT: potential for mismatch of file information here.
  # dependence on file list order is wrong

  s_title_info="[$(fn_file_info "$s_title_template")]" # use first video file found as template
  s_title_template="$(echo "$s_title_template" | sed 's/'"$(fn_regexp "$s_title_info" "sed")"'//')"
  s_title_template="${s_title_template%.*}"
  s_title_path="${s_title_template%/*}/"
  [[ ! -d "$s_title_path" || x$(cd "$s_title_path" && pwd) == "x$(pwd)" ]] && s_title_path=""
  s_title_template="$(echo ${s_title_template##*/} | awk '{gsub(" ",".",$0); print tolower($0)}')"

  # mask?
  s_mask_default=""
  IFS=$'\|'; s_mask=($(fn_file_multi_mask "$s_title_template")); IFS=$IFSORG
  if [ ${#s_mask[@]} -gt 0 ]; then
    [ $DEBUG -ge 5 ] && echo "[debug] mask found, parts: ${s_mask[@]}, setting generic"
    s_mask_default=${s_mask[0]}
    s_title_template=$(echo "$s_title_template" | sed 's/\[\?'"$(fn_regexp "${s_mask[2]}" "sed")"'\]\?/['$s_mask_default']/')
  fi

  # filters
  s_title_template="$(fn_filter "$s_title_template" \
                       "--repeat" "$filters_cmd" \
                       "${filters_rc:-/}" \
                       "$filters_mod" \
                       "$filters_codecs" \
                       "$filters_misc" "$filters_misc2" "$filters_misc3" "$filters_misc4" \
                       "--repeat" "$filters_repeat_misc" \
                       "--repeat" "$filters_repeat_misc2")"

  # set title based on search / template file name / mask / file info
  # parts
  s_search_="$(echo "$s_search" | awk '{gsub(" ",".",$0); print tolower($0)}')"
  if [ -n "$(echo "$s_title_template" | grep -i "$(fn_regexp "$s_search_" "grep")")" ]; then
    s_title="$s_title_template.$s_title_info"
  elif [ -n "$s_mask_default" ]; then
    s_title="$s_search_.[$s_mask_default].${s_title_template#*\[${s_mask_default}\]}.$s_title_info"
  else
    s_title="$s_search_.$s_title_info"
  fi

  echo -e "set the title template$([ $l_files -gt 1 ] && echo ". supported multi-file masks: '#of#', 's##e##'"). note ']/[' are fixed title delimiters" 1>&2
  b_retry=1
  while [ $b_retry -gt 0 ]; do
      echo -n ${clr["hl"]} 1>&2 && read -e -i "$s_title" s_title && echo -n ${clr["off"]} 1>&2
    echo -ne "confirm title: '$s_title'? [(y)es/(n)o/e(x)it] " 1>&2
    b_retry2=1
    while [ $b_retry2 -gt 0 ]; do
      result=
      read -s -n 1 result
      case "$result" in
        "y"|"Y") echo "$result" 1>&2; b_retry2=0; b_retry=0 ;;
        "n"|"N") echo "$result" 1>&2; b_retry2=0 ;;
        "x"|"X") echo "$result" 1>&2; return 0 ;;
      esac
    done
  done
  # deconstruct title
  if [ -n "$(echo $s_title | grep -iP '\[')" ]; then
    s_title_extra=${s_title##*[}
    if [ ${#s_title_extra} -gt 0 ]; then
      s_title_extra="[$s_title_extra"
      s_title="$(echo "${s_title:0:$((${#s_title} - ${#s_title_extra}))}" | sed 's/\.*$//')"
    fi
    # recover (potentially modified) default multi-file mask
    [ $DEBUG -ge 1 ] && echo "s_mask: '${s_mask[@]}', s_mask_default: '$s_mask_default'" 1>&2
    IFS=$'\|'; s_mask=($(fn_file_multi_mask "$s_title")); IFS=$IFSORG
    [ $DEBUG -ge 1 ] && echo "s_mask: '${s_mask[@]}', s_mask_default: '$s_mask_default'" 1>&2
    # correct default mask to be based on total files (where necessary)
    if [[ $s_mask && -n "$(echo "${s_mask[0]}" | sed -n '/of/p')" ]]; then
      s_mask_default=$(echo "$s_mask_default" | sed 's/\(#\+of\)#/\1'$l_files'/')
      [ $DEBUG -ge 1 ] && echo "s_mask: '${s_mask[@]}', s_mask_default: '$s_mask_default'" 1>&2
      IFS=$'\|'; s_mask=($(fn_file_multi_mask "$s_title" $s_mask_default)); IFS=$IFSORG
      [ $DEBUG -ge 1 ] && echo "s_mask: '${s_mask[@]}', s_mask_default: '$s_mask_default'" 1>&2
      # remember to update the title too, ensuring the modified default
      # mask is there for templated replacement in the latter files loop
      s_title=$(echo "$s_title" | sed 's/\(#\+of\)#/\1'$l_files'/')
      [ $DEBUG -gt 0 ] && echo "#s_title: '$s_title'" 1>&2
    fi

    s=""; while [ "x$s_title_extra" != "x$s" ]; do s="$s_title_extra"; s_title_extra="$(echo "$s_title_extra" | sed 's/\(\[\.*\]\|(\.*)\|^\.\|\.$\)//g')"; done
    s=""; while [ "x$s_title_extra" != "x$s" ]; do s="$s_title_extra"; s_title_extra="$(echo "$s_title_extra" | sed 's/\.\././g')"; done
  fi

  [ $DEBUG -gt 0 ] && echo "[debug] title: '$s_title', extra: '$s_title_extra'" 1>&2

  # structure files
  # move
  s_short_title=${s_title%%[*} && s_short_title=${s_short_title%.}
  $cmdmd -p "$s_short_title"
  info="$s_short_title/info"
  declare -A f_dirs
  for f in "${s_files[@]}"; do
    $cmdmv "$f" "$s_short_title/" #2>/dev/null
    # collect dirs
    f2="${f%/*}"
    [[ -d "$f2" && "x$d" != "" &&  x$(cd "$f2" && pwd) != "x$(pwd)" ]] && f_dirs["$f2"]="$f2"
  done
  # clean up. subdirs needs to be removed first. loop as many times
  # as is directories achieves this, crudely!
  for l in $(seq 1 1 ${#f_dirs[@]}); do
    for d in "${f_dirs[@]}"; do rmdir "$d" >/dev/null 2>&1; done
  done
  #[ $DEBUG -eq 0 ] && { cd $s_title || return 1; }
  # rename
  # trim dummy extra info stub, sent as separate parameter to
  # fn_file_target function
  s_title2="$(echo "${s_title%[*}" | sed 's/\(^\.\|\.$\)//g')"

  #IFSORG=$IFS; IFS=$'\n'; files=($(fn_files "$n")); IFS=$IFSORG; for f2 in "${files[@]}"; do n2=${f2##*.}; [ ! -e "$n.$n2" ] && mv -i "$f2" "$n.$n2"; done; done
  IFS=$'\n'; s_files2=($(find "./$s_short_title/" -maxdepth 1 -type f -iregex '^.*\.\('"$(echo $VIDEXT\|$VIDXEXT\|$EXTEXT | sed 's|\||\\\||g')"'\)$' | sort -i)); IFS=$IFSORG
  if [ $TEST -ge 1 ]; then
    # use original files as we didn't move any!
    s_files2=()
    for f in "${s_files[@]}"; do [ -n "$(echo "$f" | sed -n '/^.*\.\('"$(echo $VIDEXT\|$VIDXEXT\|$EXTEXT | sed 's|\||\\\||g')"'\)$/p')" ] && s_files2[${#s_files2[@]}]="$f"; done
  fi
  [ $DEBUG -gt 0 ] && echo "#s_files2: ${#s_files2[@]}, s_files2: '${s_files2[@]}'" 1>&2
  for f in "${s_files2[@]}"; do
    # go lower case, remove spaces, remove path
    f2="$(echo "${f##*/}" | awk '{gsub(" ",".",$0); print tolower($0)}')"

    IFS=$'|'; s_mask=($(fn_file_multi_mask "$f2" "" "$s_mask_default")); IFS=$IFSORG
    [ $DEBUG -gt 0 ] && echo "s_mask: '${s_mask[@]}'" 1>&2

    if [ -n "$filters_cmd" ]; then
      # we need to manipulate the target (s_title2) before it goes for its final name fixing (fn_file_target)
      # providing filter terms means the s_title2 contains only the stub
      # apply filters
      if [ -n "${s_mask[1]}" ]; then
        # dynamic title part and additional file info pre-filter
        s_target="$(echo "${f2%.*}" | sed 's/^.*'"$(fn_regexp "${s_mask[1]}" "sed")"'\]*//')"
      else
        # no delimiter. so we need to use any info in the original
        # filename that isn't in our fixed title
        delimiters='][)([:space:],._-'
        a_=($(echo "$s_title2" | sed 's/['"$delimiters"']/ /g'))
        [ $DEBUG -ge 2 ] && echo "[debug] filtered title tokens '[${#a_[@]}] ${a_[@]}' from file name '$f2'" 1>&2
        s_="$f2"
        for s__ in ${a_[@]}; do s_=$(echo "$s_" | sed 's/['"$delimiters"']*'"$s__"'['"$delimiters"']*/../Ig'); done
        s_target="$s_title2.${s_%.*}"
        [ $DEBUG -ge 2 ] && echo "[debug] no mask, appended unused info, target: '$s_target'" 1>&2
      fi

      # filters
      s_target="$(fn_filter "$s_target" \
                  "--repeat" "$filters_cmd" \
                  "${filters_rc:-/}" \
                  "$filters_mod" \
                  "$filters_codecs" \
                  "$filters_misc" "$filters_misc2" "$filters_misc3" "$filters_misc4" \
                  "--repeat" "$filters_repeat_misc" \
                  "--repeat" "$filters_repeat_misc2")"

      if [ -n "${s_mask[1]}" ]; then
        # append filtered dynamic string to title / template prefix
        s_target="$s_title2.[$s_mask_default].$s_target"
      fi

    else
      # static
      s_target="$s_title"
    fi
    # set fileinfo
    # *IMPLEMENT: this could be removing additional info set interactively
    # update info for video files. potential for mismatch here
    [ -n "$(echo "${f##*.}" | sed -n 's/\('$(echo "$VIDEXT" | sed 's/[|]/\\\|/g')'\)/\1/p')" ] && s_title_extra="[$(fn_file_info "$f")]"
    # should use $f, but more filters would be required to cope with spaces etc.
    s_target=$(fn_file_target "$f2" "$s_target" "$s_title_extra")
    # strip failed multifile suffixes
    s_target=$(echo "$s_target" | sed 's/\.*\(\.\['$s_mask_default'\]\)\.*/./')

    [ $DEBUG -ge 1 ] && echo "s_target: '$s_target' from f: '$f', s_title2: '$s_title2', s_title_extra: '$s_title_extra', s_mask_default: $s_mask_default" 1>&2

    if [[ -n "$s_target" && "x$f" != "x./$s_short_title/$s_target" ]]; then
      # move!
      if [ $TEST -eq 0 ]; then
        while [ -f "./$s_short_title/$s_target" ]; do
          # target already exists
          if [ -z "$(diff -q "$f" "./$s_short_title/$s_target")" ]; then
            # dupe file
            [ $DEBUG -ge 1 ] && echo "file: '$f' is identical to pre-existing target: '$s_target'. assuming duplicate and removing file" 1>&2
            s_target=""
            rm "$f"
            break
          else
            echo -e "target file '$s_target' for '${f##*/}' already exists, rename target or set blank to skip" 1>&2
            echo -n ${clr["hl"]} 1>&2 && read -e -i "$s_target" s_target && echo -n ${clr["off"]} 1>&2
            [ -z "$s_target" ] && break
          fi
        done
      fi
      if [ -n "$s_target" ]; then
        # log
        [ $TEST -eq 0 ] && echo "${f##*/} -> $s_target" | tee -a "$info"
        # move
        $cmdmv "$f" "./$s_short_title/$s_target"
      fi
    fi
  done

  [ $verbose -ge 1 ] && echo "[info] structure '$s_short_title' created" 1>&2

  [ ! -t 1 ] && echo "$pwd/$s_short_title"
  return 0
}

fn_rate() {
  # move files to the local ratings hierarchy (or default rating
  # hierarchy location if we cannot find the local hierarchy 'nearby'

  [ $DEBUG -ge 1 ] && echo "[debug fn_rate]" 1>&2

  cmdmd="$([ $TEST -gt 0 ] && echo "echo ")$CMDMD"
  cmdmv="$([ $TEST -gt 0 ] && echo "echo ")$CMDMV"
  cmdrm="$([ $TEST -gt 0 ] && echo "echo ")$CMDRM"
  cmdcp="$([ $TEST -gt 0 ] && echo "echo ")$CMDCP"

  # args
  [ $# -eq 0 ] && echo "[user] search string / target parameter required!" && return 1

  # rating (optional)
  [ $# -gt 1 ] && [ -n "$(echo $1 | sed -n '/^[0-9]\+$/p')" ] && l_rating="$1" && shift
  # search
  s_search="$1" && shift
  #rating (optional)
  [ $# -gt 0 ] && [ -n "$(echo $1 | sed -n '/^[0-9]\+$/p')" ] && l_rating="$1" && shift
  # path
  if [ $# -gt 0 ] && [ -n "$(echo $1 | sed -n '/^[0-9]\+$/p')" ]; then
    [ ! -d "$1" ] && echo "[user] the ratings base path '$1' is invalid" && return 1
    s_path_base="$1" && shift
  fi
  # rating (optional)
  [ $# -gt 0 ] && [ -n "$(echo $1 | sed -n '/^[0-9]\+$/p')" ] && l_rating="$1" && shift

  # source
  source=""
  if [ -d "$s_search" ]; then
    source="$(cd "$s_search" && pwd)"
  elif [ -d $s_search* ] 2>/dev/null; then
    source="$(cd $s_search* && pwd)"
  else
    # auto local source

    # get list of associated files in pwd
    IFS=$'\n'
    s_files=($(fn_files silent "$s_search"))
    x=$? && [ $x -ne 0 ] && return $x
    [ $DEBUG -ge 1 ] && echo "[debug fn_rate] fn_files results: count=${#s_files[@]}" 1>&2
    IFS=$IFSORG
    # if all are under the same subdirectory then assume that is a
    # source structure, otherwise, structure those files interactively
    if [ ${#s_files[@]} -eq 1 ]; then
      # is it inside a dir structure
      f="${s_files[0]}"
      s0=${f##*/} #file
      s1=${f%/*} #path
      s2=${s1##*/} #parent dir
      if [[ ${#s2} -gt 0 && "x${s0:0:${#s2}}" == "x$s2" ]]; then
        source="$s1" # structured
      else
        # option to structure?
        echo -n "[user] structure single file '${s_files[0]}'? [(y)es/(n)o/e(x)it]:  " 1>&2
        b_retry=1
        while [ $b_retry -eq 1 ]; do
          echo -en '\033[1D\033[K'
          read -n 1 -s result
          case "$result" in
            "y" | "Y") echo -n $result; b_retry=0; source="" ;;
            "n" | "N") echo -n $result; b_retry=0; source=${s_files[0]} ;;
            "x" | "X") echo -n $result; b_retry=0; echo ""; return 0 ;;
            *) echo -n " " 1>&2
          esac
        done
        echo ""
      fi
    elif [ ${#s_files[@]} -gt 1 ]; then
      for f in "${s_files[@]}"; do
        f2=${f%/*}
        if [ -z "$source" ]; then
          source="$f2"
        else
          # this disables auto rating when our working directory is the
          # same as the target files. necessary, but also defeats use
          # case where we are in a legitimate structure directory
          [[ "x$f2" != "x$source" || "x$(cd "$f2" && pwd)" == "x$PWD" ]] && source="" && break
        fi
      done
    fi
    # global search
    l_type=0 # 0 auto, 1 interactive
    while [ $l_type -lt 2 ]; do
      if [ -z "$source" ]; then
        s_=$(fn_search "-ss" $([ $l_type -eq 1 ] && echo "-i") "-x" "$VIDEXT" "$s_search")
        res=$? && [ $res -ne 0 ] && return $res
        IFS=$'\n'; s_files=($(echo "$s_")); IFS=$IFSORG
        [ $DEBUG -ge 1 ] && echo "[debug fn_rate] fn_search results: count=${#s_files[@]}" 1>&2
        # filter valid
        s_files2=()
        for f in "${s_files[@]}"; do [ -f "$f" ] && s_files2[${#s_files2[@]}]="$f"; done;
        s_files=(${s_files2[@]})
        if [ ${#s_files[@]} -eq 1 ]; then
          # is it inside a dir structure
          f="${s_files[0]}"
          s0=${f##*/} #file
          s1=${f%/*} #path
          s2=${s1##*/} #parent dir
          if [[ ${#s2} -gt 0 && "${s0:0:${#s2}}" == "$s2" ]]; then
            source="$s1" # structured
          else
            # option to structure?
            echo -n "[user] structure single file '${s_files[0]}'? [(y)es/(n)o/e(x)it]:  " 1>&2
            b_retry=1
            while [ $b_retry -eq 1 ]; do
              echo -en '\033[1D\033[K'
              read -n 1 -s result
              case "$result" in
                "y" | "Y") echo -n $result; b_retry=0; source="" ;;
                "n" | "N") echo -n $result; b_retry=0; source=${s_files[0]} ;;
                "x" | "X") echo -n $result; b_retry=0; echo ""; return 0 ;;
                *) echo -n " " 1>&2
              esac
            done
            echo ""
          fi
          l_type=$((l_type + 1))
        elif [ ${#s_files[@]} -gt 1 ]; then
          # if all files are under the same subdirectory then assume
          # that is the stucture
          # if there are multiple subdirectories all under a common
          # subdirectory, find and use the common root and structure
          # those files interactively
          # if there are multi subdirectories, choose the desired base
          sources=()
          lastbase=""
          for f in "${s_files[@]}"; do
            d=${f%/*}
            if [ -z "$lastbase" ]; then
              sources=("$d")
              l_type=$((l_type + 1))
            else
              # disables auto rating when multiple directories /
              # structures have been found, or our working directory
              # is the same as the target files. necessary, but also
              # defeats use case where we are in a legitimate structure
              # directory
              [ "x$d" = "x$lastbase" ] && continue
              sources=("${sources[@]}" "$d")
            fi
            [ $DEBUG -ge 1 ] && echo "[debug fn_rate] found files in: '$d'" 1>&2
            lastbase="$d"
          done
          [ $DEBUG -ge 1 ] && echo "[debug fn_rate] found ${#sources[@]} source dir$([ ${#sources[@]} -ne 1 ] && echo "s") with file(s) containing search term" 1>&2
          if [ ${#sources[@]} -eq 1 ]; then
            source="${sources[0]}"
            [ $DEBUG -ge 1 ] && echo "[debug fn_rate] source dir set to '$source'" 1>&2
          else
            # strip same subdirectory roots?
            sources2=()
            for d2 in "${sources[@]}"; do
              if [ ${#sources2[@]} -eq 0 ]; then
                [ $DEBUG -ge 1 ] && echo -e "[debug fn_rate] adding d2: '$d2'" 1>&2
                sources2=("$d2")
              else
                lidx=0
                for d3 in "${sources2[@]}"; do
                  # if d2 is a base of d3 then ignore d3, else add it!
                  # if d3 is a base of d2 then replace d2 with d3, else
                  # add it!
                  [ $DEBUG -ge 1 ] && echo -e "[debug fn_rate] testing\nd2: '$d2'\nd3: '$d3'" 1>&2
                  if [ ${#d2} -gt ${#d3} ]; then
                    # d2 could be a subdirectory of d3..
                    [ -z "$(echo "$d2" | sed -n '/.*'"$(fn_regexp "$d3" "sed")"'.*/p')" ] &&
                      { sources2=("${sources2[@]}" "$d2") &&
                        [ $DEBUG -ge 1 ] && echo -e "[debug fn_rate] adding d2: '$d2'" 1>&2; }
                  else
                    # d3 could be a subdirectory of d2..
                    [ -n "$(echo "$d3" | sed -n '/.*'"$(fn_regexp "$d3" "sed")"'.*/p')" ] &&
                      { sources2[$lidx]="$d2" &&
                        [ $DEBUG -ge 1 ] && echo -e "[debug fn_rate] replacing d3 with d2: '$d2'" 1>&2; } ||
                      { sources2=("${sources2[@]}" "$d3") &&
                        [ $DEBUG -ge 1 ] && echo -e "[debug fn_rate] adding d2: '$d2'" 1>&2; }
                  fi
                  lidx=$((lidx + 1))
                done
              fi
            done
            [ $DEBUG -ge 1 ] && echo "[debug fn_rate] stripped $((${#sources[@]} - ${#sources2[@]})) subdirectories from sources list" 1>&2
            if [ ${#sources[@]} -eq 1 ]; then
              source="${sources[0]}"
              [ $DEBUG -ge 1 ] && echo "[debug fn_rate] source dir set to '$source'" 1>&2
            else
              # choose!
              lidx=0
              b_retry=1
              while [[ $b_retry -eq 1 && $lidx -lt ${#sources2[@]} ]]; do
                echo -n "[user] multiple source dirs found, use '${sources2[$lidx]}'? [(y)es/(n)o/e(x)it]:  " 1>&2
                b_retry2=1
                while [ $b_retry2 -eq 1 ]; do
                  echo -en '\033[1D\033[K'
                  read -n 1 -s result
                  case "$result" in
                    "y" | "Y") echo -n $result; b_retry2=0; b_retry=0; source="${sources2[$lidx]}" ;;
                    "n" | "N") echo -n $result; b_retry2=0; lidx=$((lidx + 1)) ;;
                    "x" | "X") echo -n $result; b_retry2=0; echo ""; return 0 ;;
                    *) echo -n " " 1>&2
                  esac
                done
                echo ""
              done
            fi
          fi
        fi
      fi
      l_type=$((l_type + 1))
    done

    [ $DEBUG -ge 1 ] && echo "[debug fn_rate] source: '$source'" 1>&2

    # manual local re-structure
    if [ -z "$source" ]; then
      source="$(fn_structure --silent "$s_search")"
      x=$? && [ $x -ne 0 ] && return $x
    fi

  fi

  if [ -z "$s_path_base" ]; then
    # iterate up file hierarchy looking for 'watched' folder. use a default if failure
    wd="${source%/*}"
    b_retry=1
    while [ $b_retry -eq 1 ]; do
      if [ -e "$wd/watched/" ]; then
        b_retry=0
        s_path_base="$wd/watched/"
      elif [ -z "$wd" ]; then
        b_retry=0
      else
        wd="${wd%/*}"
      fi
    done
    if [ -z "$s_path_base" ]; then
      s_path_base="$PATHRATINGSDEFAULT"
      [ ! -d $s_path_base ] && $cmdmd $PATHRATINGSDEFAULT
    fi
  fi
  [ ! -d "$s_path_base" ] && echo "[user] the default ratings base path '$s_path_base' is invalid" 1>&2 && return 1
  [ "x${s_path_base:$((${#s_path_base} - 1))}" != "x/" ] && s_path_base="$s_path_base/"

  if [ ! "$l_rating" ]; then
    b_retry=1
    while [ $b_retry -eq 1 ]; do
      echo -en "[user] enter an integer rating between 1 and 10 for '${source##*/}' or leave empty for unrated (where file structure is pushed to the root of the 'watched' dir): " 1>&2
      read result
      case "$result" in
        [1-9]|10|"") b_retry=0; l_rating=$result ;;
        #*) echo -en "\033[u\033[A\033[K" ;;
        *) echo -en "\033[A\033[2K" ;;
      esac
    done
    #echo -en "\033[7h" 1>&2
  fi
  echo -e "source: '$source'\ntarget: '$s_path_base$l_rating'"
  $cmdmd "$s_path_base$l_rating" 2>/dev/null 1>&2

  if [ -e "$s_path_base$l_rating/${source##*/}" ]; then
    echo -en "[user] path '$s_path_base$l_rating/${source##*/}' exists, overwrite? [(y)es/(no):  " 1>&2
    b_retry=1
    while [ $b_retry -eq 1 ]; do
      echo -en '\033[1D\033[K'
      read -n 1 -s result
      case "$result" in
        "y" | "Y") echo -n $result; b_retry=0 ;;
        "n" | "N") echo -n $result; echo "" && return 1 ;;
        *) echo -n " " 1>&2
      esac
    done
    echo ""
  fi

  target="$s_path_base$l_rating"

  dev_source="$(stat --format '%d' $source)"
  dev_target="$(stat --format '%d' $target)"
  if [ "$dev_source" = "$dev_target" ]; then
    [ $DEBUG -ge 1 ] && echo "[debug fn_rate] local move" 1>&2
    $cmdmv "$source" "$target" 2>/dev/null 1>&2 &
  else
    [ $DEBUG -ge 1 ] && echo "[debug fn_rate] safe copy/delete move" 1>&2
    $cmdcp "$source" "$target/" && $cmdrm "$source" 2>/dev/null 1>&2 &
  fi

  return 0
}

fn_reconsile() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_reconsile]" 1>&2

  file="$1"
  [[ ! -e $file || -z "$file" ]] && echo "invalid source file '$file'" && return 1
  file2="$file"2
  [ -e $file2 ] && echo "" > "$file2"

  MINSEARCH=5
  l=0
  l_max=0
  while read line; do
    s_search="$(echo "${line%%|*}" | sed 's/\s/\./g' | awk -F'\n' '{print tolower($0)}')"
    s_="$(fn_search "-ss" "$s_search")"
    res=$? && [ $res -ne 0 ] && return $res
    IFS=$'\n'; a_found=($(echo "$s_")); IFS=$IFSORG
    s="$line"
    for s2 in "${a_found[@]}"; do s="$s\t$s2"; done
    echo -e "$s" >> "$file2"
    l=$((l + 1))
    [ $l -eq $l_max ] && break
  done < $file
  #sed -i -n '1b;p' "$file2"
  return 0
}

fn_fix() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_fix]" 1>&2

  [ -f "$CMDFLVFIXER" ] && echo "missing flvfixer.php" 1>&2

  [ $# -ne 1 ] && echo "single source file arg required" && return 1
  echo -e "\n[cmd] php $CMDFLVFIXER\n --in '$1'\n --out '$1.fix'"
  echo -e "[orig] $(ls -al "$1")"
  php "$CMDFLVFIXER" --in "$1" --out "$1.fix" 2>/dev/null
  chown --reference "$1" "$1.fix"

  echo -e "\n[cmd] mv file file.dead; mv file.fix file"
  mv "$1" "$1.dead"
  mv "$1.fix" "$1"
  echo -e "[new] $(ls -al "$1")\n"
}

fn_sync() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_sync]" 1>&2

  [ ${#args[@]} -ne 2 ] && echo "source file and offset args required" && return 1
  file="$1"
  offset="$2" && offset=$(fn_position_numeric_to_time $offset 4)
  target="${file%.*}.sync.${file##*.}"

  echo -e "\n#origial video runtime: $(fn_position_numeric_to_time $($CMDINFOMPLAYER "$file" 2>/dev/null | grep "ID_LENGTH=" | cut -d '=' -f2) 4)\n"
  [ $? -ne 0 ] && return 1
  echo command: ffmpeg -y -itsoffset $offset -i "$file" -i "$file" -map 0:v -map 1:a -c copy "$target"
  ffmpeg -y -itsoffset $offset -i "$file" -i "$file" -map 0:v -map 1:a -c copy "$target"
  [ $? -ne 0 ] && return 1
  echo -e "\n#new video runtime: $(fn_position_numeric_to_time $($CMDINFOMPLAYER "$target" 2>/dev/null | grep "ID_LENGTH=" | cut -d '=' -f2) 4)\n"
  [ $? -ne 0 ] && return 1
  chown --reference "$file" "$target"
}

fn_calc_video_rate() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_calc_video_rate]" 1>&2

  # output size in kbps
  [ $# -ne 3 ] && echo "target size, audio size and length args required" && return 1
  t_size="$1" && shift
  kt_size=1 && [ "x${t_size:$((${#t_size} - 1))}" = "xM" ] && kt_size="(1024^2)"
  t_size="$(echo "$t_size" | sed 's/[Mb]//g')"
  a_size="$1" && shift
  ka_size=1 && [ "x${a_size:$((${#a_size} - 1))}" = "xM" ] && ka_size="(1024^2)"
  a_size="$(echo "$a_size" | sed 's/[Mb]//g')"
  length="$1" && shift
  k_length=1 && [ "x${length:$((${#length} - 1))}" != "xs" ] && k_length="60"
  length="$(echo "$length" | sed 's/[ms]//g')"

  echo "target: $(math_ "((($t_size*$kt_size)-($a_size*$ka_size))*8/1024)/($length*$k_length)")kbps"
}

fn_edit() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_edit]" 1>&2

  target="$(pwd)" && [ $# -gt 0 ] && target="$1" && shift
  filter=".*" && [ $# -gt 0 ] && filter="$1" && shift

  [ ! -d "$target" ] && echo "[error] invalid target directory '$target'"
  target=$(cd "$target" && echo "$PWD")

  IFS=$'\n'; files=($(find "$target" -maxdepth 1 -iregex '^.*\(mp4\|mkv\|avi\)$' | sort -i)); IFS=$IFSORG
  for f in "${files[@]}"; do
    # short-circuit with filter
    [ -z "$(echo "$f" | sed -n '/'$filter'/p')" ] && continue

    echo "#source: $f"
    n="${f%.*}"; n="${n##*/}"

    [ ! -d "$target/$n" ] && mkdir -p "$target/$n"

    [ ! -f "$target/$n/$n.vid" ] && ffmpeg -y -i "$f" -map 0:v:0 -c:v huffyuv -f avi "$target/$n/$n.vid";
    [ ! -f "$target/$n/$n.aud" ] && ffmpeg -y -i "$f" -map 0:a:0 -c:a copy -f mp4 "$target/$n/$n.aud";

    IFS=$'\n'; mp4s=($(find $target/$n/ -maxdepth 1 -iregex '^.*mp4$' | sort -i)); IFS=$IFSORG
    if [ ${#mp4s[@]} -gt 0 ]; then
      rm $target/$n/files
      echo "converting part files to transport stream format"
      for v in "${mp4s[@]}"; do ts="${v%.*}.ts"; [ ! -f "$ts" ] && ffmpeg -i "$v" -map 0:v -c:v copy -bsf h264_mp4toannexb -f mpegts "$ts"; echo "file '$(echo "$ts" | sed "s/'/'\\\''/g")'" >> $target/$n/files; done;
      echo "concatenating video streams"
      ffmpeg -y -f concat -i $target/$n/files -map 0:v -c:v copy -f mp4 $target/$n/$n.mp4.concat || return 1
      echo "re-muxing a/v"
      ffmpeg -y -i $target/$n/$n.mp4.concat -i $f -map 0:v -c:v copy -map 1:a -c:a copy -f mp4 $f.mod || return 1
    fi
  done
}

fn_calc_dimension() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_calc_dimension]" 1>&2

  [ $# -ne 3 ] && echo "syntax: fn_calc_dimension original_dimensions=1920x1080 scale_dimension=height|width target_dimension_other=x" && return 1
  original_dimensions=$1
  scale_dimension=$2
  target_dimension_other=$3

  [[ "x$scale_dimension" != "xwidth" && "x$scale_dimension" != "xheight" ]] &&
    echo invalid scaled dimension && return 1
  if [ "x$scale_dimension" = "xwidth" ]; then
    original_dimension=${original_dimensions%x*}
    original_dimension_other=${original_dimensions#*x}
  else
    original_dimension=${original_dimensions#*x}
    original_dimension_other=${original_dimensions%x*}
  fi

  scaled_dimension="$(math_ $target_dimension_other/$original_dimension_other*$original_dimension 0)"

  int=0
  inc=1
  [ "$(echo "scale=0; $scaled_dimension % 8 < 4" | bc)" -eq 1 ] && inc=-1
  while [ $int -ne 1 ]; do
     divisor="$(math_ $scaled_dimension/8 2)"
     [ "x${divisor##*.}" = "x00" ] && int=1 || scaled_dimension=$((scaled_dimension + inc))
  done
  echo $scaled_dimension
}

fn_remux() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_remux]" 1>&2

  [ $# -lt 1 ] && help && echo "missing arg" && return 1

  cmdffmpeg="ffmpeg"
  cmdffmpeg="$(echo $([ $TEST -gt 0 ] && echo "echo ")$cmdffmpeg)"

  source="$1" && shift
  target="${source%.*}.remux.mp4"

  profile=2p6ch
  [ $# -gt 0 ] && [ -n "$(echo "$1" | sed -n '/^\(2p6ch[0-9]\?\|1p2ch[0-9]\?\)$/p')" ] && profile="$1" && shift

  [ $# -gt 0 ] && [ -n "$(echo "$1" | sed -n '/^\([0-9]\+\|auto\)$/p')" ] && width=$1 && shift
  [ $# -gt 0 ] && [ -n "$(echo "$1" | sed -n '/^\([0-9]\+\|auto\)$/p')" ] && height=$1 && shift
  if [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/^\([0-9]\+[kK]\|auto\|copy\)$/p')" ]]; then
     [ "x$1" != "xauto" ] && vbr="$1"
     shift
  fi
  if [[ $# -gt 0 && -n "$(echo "$1" | sed -n '/^\([0-9]\+[kK]\|auto\|copy\)$/p')" ]]; then
    [ "x$1" != "xauto" ] && abr="$1"
    shift
  fi

  passes=1
  [[ $# -gt 0 && -n "$(echo $1 | sed -n '/^[1-2]$/p')" ]] && passes=$1 && shift

  vstream=0
  [[ $# -gt 0 && -n "$(echo $1 | sed -n '/^[0-9]$/p')" ]] && vstream=$1 && shift
  astream=0
  [[ $# -gt 0 && -n "$(echo $1 | sed -n '/^[0-9]$/p')" ]] && astream=$1 && shift

  # profile base
  case "$profile" in
     2p6ch*)
       vcdc="hevc"
       [ "x$vbr" = "xcopy" ] && vcdc="copy"
       vbr="${vbr:-"1750k"}"
       acdc="aac"
       [ "x$abr" = "xcopy" ] && acdc="copy"
       abr="${abr:-"320k"}"
       channels=6
       preset="medium"
       defwidth="auto"
       defheight=720
       ;;
     1p2ch*)
       vcdc="hevc"
       [ "x$vbr" = "xcopy" ] && vcdc="copy"
       vbr="${vbr:-"1500k"}"
       acdc="aac"
       [ "x$abr" = "xcopy" ] && acdc="copy"
       abr="${abr:-"256k"}"
       channels=2
       af="aresample=matrix_encoding=dplii"
       preset="veryfast"
       defheight="auto"
       defwidth=1280
       ;;
     *)
       echo "unknown profile"
       return 1
       ;;
  esac

  # profile tweaks
  case $profile in
    "2p6ch2")
      defheight="auto"
      ;;
    "1p2ch2")
      defwidth="auto"
      ;;
  esac

  scale=""
  if [[ -n "$height" || -n "$width" ]] ||
     [[ "x$defheight" != "xauto" || "x$defwidth" != "xauto" ]]; then
    dimensions="$(fn_file_info 3 $source | cut -d'|' -f 3)"
    [[ -z "$height" && -z "$width" ]] && height=$defheight && width=$defwidth
    [[ -z "$height" || "x$height" == "xauto" ]] && height="$(fn_calc_dimension $dimensions height ${width:-$defwidth})"
    [[ -z "$width" || "x$width" == "xauto" ]] && width="$(fn_calc_dimension $dimensions width ${height:-$defheight})"
    scale="$width:$height"
  fi

  case $passes in
    1)
      cmd="$cmdffmpeg -y -i file:$source -map 0:v:$vstream -preset $preset -vcodec $vcdc"
      [ "x$vcdc" != "xcopy" ] && cmd="$cmd -b:v $vbr -vf crop=$crop$([ -n "$scale" ] && echo ,scale=$scale) -threads:0 9 -map 0:a:$astream -acodec $acdc"
      [ "x$acdc" != "xcopy" ] && cmd="$cmd -b:a $abr -ac $channels $([ -n "$af" ] && echo -af $af)"
      cmd="$cmd -f ${target##*.} file:$target"
      echo "[$profile (pass 1)] $cmd"
      exec $cmd
      [ $? -eq 0 ] && echo "# pass complete" || { echo "# pass failed" && return 1; }
      ;;
    2)
      cmd="$cmdffmpeg -y -i file:$source -map 0:v:$vstream -preset $preset -vcodec $vcdc"
      [ "x$vcdc" != "xcopy" ] && cmd="$cmd -b:v $v_bitrate -vf crop=$crop$([ -n "$scale" ] && echo ,scale=$scale)"
      cmd="$cmd -pass 1 -threads:0 9 -f ${target##*.} /dev/null"
      echo "[$profile (pass 1)] $cmd"
      exec $cmd
      [ $? -eq 0 ] && echo "# pass 1 complete" || { echo "# pass 1 failed" && return 1; }

      cmd="$cmdffmpeg -y -i file:$source -map 0:v:$vstream -preset $preset -vcodec $vcdc"
      [ "x$vcdc" != "xcopy" ] && cmd="$cmd -b:v $v_bitrate -vf crop=$crop$([ -n "$scale" ] && echo ,scale=$scale)"
      cmd="$cmd -pass 2 -map 0:a:$astream -acodec $acdc"
      [ "x$acdc" != "xcopy" ] && cmd="$cmd -ab $a_bitrate -ac $channels $([ -n "$af" ] && echo -af $af)"
      cmd="$cmd -threads:0 9 -f ${target##*.} file:$target"
      echo "[$profile (pass 1)] $cmd"
      exec $cmd
      [ $? -eq 0 ] && echo "# pass 2 complete" || { echo "# pass 2 failed" && return 1; }
      ;;
  esac
}

fn_names()
{
  [ $DEBUG -ge 1 ] && echo "[debug fn_names]" 1>&2

  cmdmv="$(echo $([ $TEST -gt 0 ] && echo "echo ")$CMDMV)"

  [ $# -lt 1 ] && \
    echo "missing set name" && return 1
  set="$1" && shift

  source="names"
  ROOTSUFFIX="./"
  [ ! -e "$source" ] && \
    [ -e "../$source" ] && ROOTSUFFIX="../"
  [ ! -e "$ROOTSUFFIX$source" ] && \
    echo "missing names list" && return 1

  source=$PWD/$ROOTSUFFIX$source
  if [ -n "$(head -n 1 $source | cut -d'|' -f3)" ]; then
    set_no="*"
    [ $# -gt 0 ] && set_no=$1 && shift
    set_dirs="$(echo ${ROOTSUFFIX}$set_no)"
    set_dirs=($set_dirs)
    for s in ${set_dirs[@]}; do
      cd $s 2>/dev/null || continue  # dir only
      while read line; do
        [ "x$(echo "$line" | awk -F'|' '{print $1}')" != "x${s##*.}" ] && continue;
        item="$(echo $line | cut -d'|' -f2)" && [ ${#item} -lt 2 ] && item="0$item";
        name=$(echo ${line##*|} | awk '{gsub(/ /,".",$0); print tolower($0)}');
        mf=(*e$item*)
        for f in "${mf[@]}"; do
          [ ! -f "$f" ] && f=(*e$item*)
          [ ! -f "$f" ] && echo "missing item '$item|$name', aborting!" && return 1
          $cmdmv "$f" "$set.[$(echo "$f" | sed -n 's/.*\[\(.*\)\].*\[.*\].*/\1/p')].$name.[${f##*[}";
        done
      done < $source
      cd - 1>&2 2>/dev/null
    done

  elif [ -n "$(head -n 1 | cut -d'|' -f2)" ]; then
    while read line; do
      item=${line%%|*};
      name=$(echo ${line#*|} | awk '{gsub(/ /,".",$0); print tolower($0)}');
      f=(*e0$item*)
      [ ! -f "$f" ] && f=(*e$item*)
      [ ! -f "$f" ] && echo "missing item '$item|$name', aborting!" && return 1
      $cmdmv "$f" "$set.["$(echo "$f" | sed -n 's/.*\[\(.*\)\].*\[.*\].*/\1/p')"].$name.[${f##*[}";
    done < $source
  fi
}

fn_rip() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_rip]" 1>&2

  target="${1:-title}"
  VIDEO=${VIDEO:-1}
  AUDIO=${AUDIO:-1}
  SUBS=${SUBS:-1}
  if [ $VIDEO -eq 1 ]; then
    echo "# extracting video track 0"
    mplayer -dvd-device . dvd://1 -dumpvideo -dumpfile "$target".vob
  fi
  if [ $AUDIO -eq 1 ]; then
    audio=($($CMDINFOMPLAYER -dvd-device . dvd://1 2>/dev/null | grep ID_AID | tr _= '|' | cut -d'|' -f 3,5))
    declare -A lang_streams
    for t in ${audio[@]}; do
      idx=${t%|*}
      lang=${t#*|}
      starget="$target" && [ ${#audio[@]} -gt 1 ] && starget="$starget.$lang"
      [ -z "${lang_streams[$lang]}" ] && lang_streams[$lang]=1 || lang_streams[$lang]=$((${lang_streams[$lang]} + 1))
      [ ${lang_streams[$lang]} -gt 1 ] && starget=$starget${lang_streams[$lang]}
      echo "# extracting audio track $idx: $lang"
      mplayer -dvd-device . dvd://1 -aid 128 -dumpaudio -dumpfile "$starget".ac3 2>/dev/null 1>&2
    done
  fi
  if [ $SUBS -gt 0 ]; then
    subs=($($CMDINFOMPLAYER -dvd-device . dvd://1 2>/dev/null | grep ID_SID | tr _= '|' | cut -d'|' -f 3,5 | grep 'en'))
    stargetidx=0
    for t in ${subs[@]}; do
      idx=${t%|*}
      lang=${t#*|}
      echo "# extracting subtitle track $idx: $lang"
      starget="$target"
      if [ $SUBS -gt 1 ]; then
        stargetidx=0
        starget="$target.$lang$idx"
      fi
      mencoder -dvd-device . dvd://1 -nosound -ovc frameno -o /dev/null -sid $idx -vobsubout $starget -vobsuboutindex $stargetidx 2>/dev/null 1>&2
      stargetidx=$(($stargetidx + 1))
    done
  fi
}

fn_util() {
  # miscellaneous utils
  [ $# -lt 1 ] && echo "[error] insufficient args, option name required" 1>&2 && return 1
  option="$1" && shift
  case "$option" in
    "structure-create-test-files")
      declare target; target="$PWD"
      declare type_; type_="${1:-"single"}"
      declare -a files
      case "$type_" in
        "single")
          IFS="|"; files=($(echo "i.jpeg|xt-xvid-tx.nfo|the.2011.dummy.xvid-cd1.avi|the.2011.dummy.xvid-cd2.avi")); IFS="$IFSORG"
          ;;
        "set")
          IFS="|"; files=($(echo "tiesto.s01e00.special.1.avi|tiesto.1x00.special.2.(1996).avi|tiesto-S1E0.special.3.xt.avi|tiesto.2005.S02e10.exit.avi|tiesto.[s01e02].mask-xt.avi")); IFS="$IFSORG"
          ;;
      esac
      mkdir -p "$target/$type" 2>/dev/null
      for f in "${files[@]}"; do touch "$target/$type/$f"; done
      ;;

    "undo")
      IFSORIG="$IFS"; IFS=$'\n'; moves=($(cat info)); IFS="$IFSORIG"
      for s in "${moves[@]}"; do
        f1=${s% -> *}
        f2=${s#* \-\> }
        echo "$f2 -> $f1"
        mv "$f2" "$f1"
      done
      ;;

    *)
      echo "[error] unsupported option '$option'" 1>&2 && return 1
    ;;
  esac
}

fn_test() {
  [ $DEBUG -ge 1 ] && echo "[debug fn_test]" 1>&2

  # functionality testing
  [ $# -lt 1 ] && echo "[error] insufficient args, function name required" 1>&2 && return 1
  func="$1" && shift
  case $func in
    "files")
      # args: [interative] search
      IFS=$'\n'; files=($($func "$@")); IFS=$IFSORG
      echo "results: count=${#files[@]}" 1>&2
      for f in "${files[@]}"; do echo "$f"; done
      ;;

    "file_info")
      declare target; target="$PWD"
      [ $# -gt 0 ] && target="$1" && shift
      [ ! -d "$target" ] && echo "[error] invalid target directory: '$target'" && return 1
      for f in "$target"/*; do
        arr=($(fn_file_info i 4 "$f/" | sed -n 's/^\[.*|\(.*\)\]\s\+.*\[\(.*\)\].*$/\1 \2/p'));
        [ "${arr[0]}" != "${arr[1]}" ] && echo "'$f': ${arr[@]}";
      done
      ;;

    "misc")
      s_files=($(find . -iregex '^.*\('"$(echo $VIDEXT\|$VIDXEXT\|nfo | sed 's|\||\\\||g')"'\)$' | sort -i))
      echo "s_files: ${s_files[@]}"
      s_files=($(find . -iregex '^.*\('"$VIDEXT\|$VIDXEXT\|nfo"'\)$' | sort -i))
      echo "s_files: ${s_files[@]}"
      s_files=($(find . -iregex '^.*\(avi\|nfo\)$' | sort -i))
      echo "s_files: ${s_files[@]}"
      ;;

    *)
      $func "$@"
      ;;
  esac
}

# process args
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  case "$arg" in
    "rx"|"regexp") regexp=1; shift ;;
    *)
      if [[ -z "$option" || ${#args[@]} -eq 0 ]]; then
        case "$arg" in
          "h"|"help"| \
          "s"|"search"| \
          "p"|"play"| \
          "pl"|"playlist"| \
          "i"|"info"| \
          "a"|"archive"| \
          "f"|"fix"| \
          "str"|"structure"| \
          "r"|"rate"| \
          "rec"|"reconsile"| \
          "kbps"| \
          "rmx"|"remux"| \
          "syn"|"sync"| \
          "e"|"edit"| \
          "n"|"names"| \
          "rip"| \
          "util"| \
          "test")
            option="$arg"
            shift
            continue
            ;;
        esac
      fi
      args[${#args[@]}]="$1"; shift ;;
  esac
done

[ $DEBUG -ge 1 ] && echo "[debug $SCRIPTNAME] option: '$option', args: '${args[@]}'" 1>&2

case $option in
  "s"|"search") fn_search "${args[@]}" ;;
  "p"|"play") fn_play "${args[@]}" ;;
  "pl"|"playlist") fn_play_list "${args[@]}" ;;
  "i"|"info") fn_files_info "${args[@]}" ;;
  "a"|"archive") fn_archive "${args[@]}" ;;
  "f"|"fix") fn_fix "${args[@]}" ;;
  "str"|"structure") fn_structure "${args[@]}" ;;
  "r"|"rate") fn_rate "${args[@]}" ;;
  "rec"|"reconsile") fn_reconsile "${args[@]}" ;;
  "kbps") fn_calc_video_rate "${args[@]}" ;;
  "syn"|"sync") fn_sync "${args[@]}" ;;
  "e"|"edit") fn_edit "${args[@]}" ;;
  "rmx"|"remux") fn_remux "${args[@]}" ;;
  "n"|"names") fn_names "${args[@]}" ;;
  "rip") fn_rip "${args[@]}" ;;
  "util") fn_util "${args[@]}" ;;
  "test") fn_test "${args[@]}" ;;
  "h"|"help") help ;;
esac
