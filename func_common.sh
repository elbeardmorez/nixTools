#!/bin/sh

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
  CMDARGS_READ_MULTICHAR=("-s" "-n")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  CMDARGS_READ_MULTICHAR=("-s" "-k")
  setopt KSH_ARRAYS
fi

# constants
DEBUG=${DEBUG:-0}
IFSORG="$IFS"
READ_MULTICHAR_TIMEOUT=1
ESCAPE_SPACE='[:space:]'
ESCAPE_PATH='])(}{$# /['
ESCAPE_BRE='].*['
ESCAPE_ERE=']}{.*?+['
ESCAPE_PERL=']}{.*?+['
ESCAPE_SED=']./-['
ESCAPE_AWK='.\|(['
TERM_RST='\033[2J\033[1;1H'  # reset terminal
TERM_CLR='\033[H\033[J\033[H'  # clear lines
LN_RHD='\033[1K'  # reset line head
LN_RTL='\033[K'  # reset line tail
LN_RST='\r\033[2K'  # reset line
CUR_SV='\033[s'  # cursor save
CUR_USV='\033[u'  # cursor unsave
CUR_INV='\033[?25l'  # cursor invisible
CUR_VIS='\033[?25h'  # cursor visible
CUR_UP='\033[A'
CUR_DWN='\033[B'
CLR_HL='\033[0001m'  # colour highlight
CLR_OFF='\033[m'  # colour off
CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_BWN='\033[0;33m'
CHR_ARR_U=$'\u21e7' #$'\u2191'
CHR_ARR_D=$'\u21e9' #$'\u2193'
CHR_ARR_L=$'\u21e6' #$'\u2190'
CHR_ARR_R=$'\u21e8' #$'\u2192'
KEY_ARR_U='\033[A'
KEY_ARR_D='\033[B'
KEY_ARR_L='\033[D'
KEY_ARR_R='\033[C'
declare -A keychr_maps
keychr_maps["$KEY_ARR_U"]="$KEY_ARR_U|$CHR_ARR_U"
keychr_maps["$KEY_ARR_D"]="$KEY_ARR_D|$CHR_ARR_D"
keychr_maps["$KEY_ARR_L"]="$KEY_ARR_L|$CHR_ARR_L"
keychr_maps["$KEY_ARR_R"]="$KEY_ARR_R|$CHR_ARR_R"

trap 'fn_observer_cleanup' EXIT

declare -A observers

fn_observer() {
  declare observer_id
  declare action_pause
  declare action_resume
  declare log

  observer_id="$1" && shift
  [ -n "${observers["$observer_id"]}" ] && \
    echo "[error] observer id is not unique" && \
    observer_cleanup && exit 1
  action_pause="$1" && shift
  [ $# -gt 0 ] && action_resume="$1" && shift
  log='/tmp/nixTools.observer_.log'
  [ $# -gt 0 ] && log="$1" && shift

  declare observer_pid
  declare observer_heartbeat_pid
  declare observer
  declare observer_socket

  observer="$(mktemp -u)"
  observer_socket="$(mktemp -u)"
  echo '#!/bin/sh
DEBUG='${DEBUG:-0}'
log='$log'

trap "exec 3<&-" EXIT

mkfifo '"$observer_socket"'
# ensure access to socket regardless of write process state via local fd
exec 3<'"$observer_socket"'
[ $DEBUG -ge 2 ] && \
  ls -al /dev/fd/ > $log
live=0
last=$live
while true; do
  beat=""
  sleep 1
  read -t 5 beat <&3
  cat <&3 >/dev/null
  [ -n "$beat" ] && live=1 || live=0
  if [ $live -ne $last ]; then
    # state changed
    if [ $live -eq 1 ]; then
      '${action_resume:-"pass=\"\""}' >> $log  # resume
    else
      '${action_pause:-"pass=\"\""}' >> $log  # pause
    fi
  fi
  [ $DEBUG -ge 1 ] && \
    echo "[debug] beat: ${beat:-"dead0"}, state: $last -> $live" >> $log
  last=$live
done
' > "$observer"
  chmod +x "$observer"

  # save pipes
  exec 6<&0 7>&1 8>&2

  # start observer
  setsid "$observer" &
  observer_pid=$!
  [ $DEBUG -ge 1 ] && echo "[debug] observer running with pid '$observer_pid'" 1>&2
  # start heartbeat
  fn_observer_heartbeat "$observer_socket" &
  observer_heartbeat_pid=$!
  [ $DEBUG -ge 1 ] && echo "[debug] observer heartbeat running with pid '$observer_heartbeat_pid'" 1>&2
  observers[${#observers[@]}]="$observer_id|$observer_pid|$observer_heartbeat_pid|$observer|$observer_socket"
}

fn_observer_heartbeat() {
  heart="$1"
  [ $DEBUG -ge 1 ] && echo "[debug] beating: $heart"
  secs=0
  sleep 2
  while true; do
    sleep 1
    echo "live$secs" > "$heart"
    secs=$((secs + 1))
  done
}

fn_observer_cleanup() {
  declare observer_
  declare -a observer
  exec 6<&- 7>&- 8>&-
  for observer_ in "${observers[@]}"; do
    IFS="|"; observer=($(echo "$observer_")); IFS="$IFSORG"
    [ $DEBUG -ge 1 ] && echo "[debug] cleaning up '${observer[0]}' observer" 1>&2
    kill -TERM ${observer[1]} 2>/dev/null  # observer proc
    kill -TERM ${observer[2]} 2>/dev/null  # heartbeat proc
    [ -e "${observer[3]}" ] && rm "${observer[3]}"  # script
    [ -e "${observer[4]}" ] && rm "${observer[4]}"  # socket
  done
}

fn_stty() {
  declare opt
  opt="$1"
  res=$(stty -a | awk -v opt="$opt" 'BEGIN{ match_=0; rx="^"opt"$" }{ for (l=0; l<=NF; l++) { if ($l ~ rx) match_=1; }} END{ print match_ }')
  echo $res
  return $res
}

fn_shell() {
  if [ -n "$BASH_VERSION" ]; then
    echo "bash"
  elif [ -n "$ZSH_VERSION" ]; then
    echo "zsh"
  else
    echo "sh"
  fi
}

fn_edit_line() {
  restore_stdin=0
  restore_stdout=0
  restore_stderr=0
  var="$1" && shift
  prompt="${1:-""}"
  [ ! -t 0 ] && restore_stdin=1 && exec 3<&0 0</dev/tty
  [ ! -t 1 ] && restore_stdout=1 && exec 4>&1 1>/dev/tty
  [ ! -t 2 ] && restore_stderr=1 && exec 5>&2 2>/dev/tty
  if [ -n "$BASH_VERSION" ]; then
    read -e -p "$prompt" -i "$var" var
  elif [ -n "$ZSH_VERSION" ]; then
    var="$(zsh -c 'var="'"$var"'"; vared -p "'"$prompt"'" var; echo "$var"')"
  fi
  [ $restore_stdin -eq 1 ] && exec <&3 3<&-
  [ $restore_stdout -eq 1 ] && exec 1>&4 4>&-
  [ $restore_stderr -eq 1 ] && exec 1>&5 5>&-
  echo "$var"
}

fn_decision() {
  declare question
  declare soptions
  declare optdelim
  declare optshow
  declare optecho
  declare -a cmd_args
  cmd_args=("${CMDARGS_READ_SINGLECHAR[@]}")
  declare -a options
  declare key
  declare tty_echo
  tty_echo=$(fn_stty "echo")
  stty -echo
  if [ $# -gt 0 ]; then
    question="$1" && shift
    echo -En "$question" 1>&2
  fi
  optdelim="/|,"
  soptions="${1:-y/n}"
  if [ $# -gt 1 ]; then
    while [ -n "$1" ]; do
      if [ ${#1} -eq 1 ]; then
        if [[ $1 -eq 0 || $1 -eq 1 ]]; then
          [ -z $optshow ] && optshow=$1 && shift && continue
          optecho=$1 && shift && continue
        fi
        optdelim="$1" && shift && continue
      fi
      soptions="$1" && shift
    done
  fi
  optshow=${optshow:-1}
  optecho=${optecho:-1}
  if [ -n "$(echo "$soptions" | sed -n '/['$optdelim']/p')" ]; then
    [ ${#optdelim} -ne 1 ] &&\
      optdelim="$(echo "$soptions" | sed -n 's/.*\(['$optdelim']\).*/\1/p')"
  else
    soptions="$(echo "$soptions" | sed 's/\(.\)/\/\1/g;s/^\///')"
    optdelim='/'
  fi
  IFS="$optdelim"; options=($(echo -En "$soptions")); IFS="$IFSORG"
  if [ $optshow -eq 1 ]; then
    soptions=""
    for option in "${options[@]}"; do
      key=""
      keychr="${keychr_maps["$option"]}"
      [ -n "$keychr" ] && key="${keychr%|*}"
      soptions+="$optdelim${CLR_HL}${key:-"$option"}${CLR_OFF}"
    done
    soptions="${soptions:${#optdelim}}"
    echo -en " [$soptions]" 1>&2
  fi
  [ $optecho -eq 1 ] &&\
     echo -n ": " 1>&2 ||\
     cmd_args[${#cmd_args[@]}]="-s"
  [ ! -t 0 ] &&\
    "[error] stdin is not attached to a suitable input device" 1>&2 && return 1
  buffer=""
  declare submatch
  submatch=""
#  clear stdin
#  read -s -t 0.1 &&\
#    while [ -n "$REPLY" ]; do REPLY="" && read -s -t 0.1; done
  while [ 1 ]; do
    [ $optecho -eq 1 ] && stty echo
    if [ -z "$submatch" ]; then
      read "${cmd_args[@]}"
    else
      read "${cmd_args[@]}" -t $READ_MULTICHAR_TIMEOUT
    fi
    stty -echo
    R="$REPLY"
    if [[ -z "$R" && -n "$submatch" ]]; then
      match="$submatch"
      break
    fi
    [ "x$R" = "x"$'\E' ] && R='\033'
    r="$(echo "$R" | tr '[A-Z]' '[a-z]')"
    map=""
    if [ ${#buffer} -gt 0 ]; then
      for keychr in "${keychr_maps[@]}"; do
        key="${keychr%|*}"
        buffer_prefix_length=$((${#key}-1))
        if [ $buffer_prefix_length -gt 0 ]; then
          buffer_prefix=""
          [ ${#buffer} -ge $buffer_prefix_length ] &&\
            buffer_prefix="${buffer:$((${#buffer}-$buffer_prefix_length))}"
          [[ "x$key" == "x$buffer_prefix$R" || "x$key" == "x\033$buffer_prefix$R" ]] &&\
            map="$key" && break
        fi
      done
    fi
    match=""
    submatch_=0
    for option in "${options[@]}"; do
      if [[ -n "$map" && "x$option" == "x$map" ]]; then
        keychr="${keychr_maps["$map"]}"
        [ -n "$keychr" ] && match="${keychr#*|}"
        break
      elif [[ -z "$map" && (-n "$submatch" && \
                            (${#option} -gt ${#submatch} && \
                             "x${option:0:$((${#submatch} + 1))}" == "x$submatch$r")) ]]; then
        submatch_=$((submatch_ + 1))
        [ "x$option" = "x$submatch$r" ] && match="$submatch$r"
      elif [[ -z "$map" && (-z "$submatch" && \
                            "x${option:0:1}" == "x$r") ]]; then
        submatch_=$((submatch_ + 1))
        [ "x$option" == "x$r" ] && match="$r"
      fi
    done
    if [ $submatch_ -eq 1 ]; then
      # unique combo / single char
      break
    elif [ $submatch_ -eq 0 ]; then
      # invalid / reset
      submatch=""
    else
      # multiple valid possibilities
      submatch+="$r"
    fi
    buffer+="$R"
  done
  if [ -n "$match" ]; then
    [ $optecho -eq 1 ] && echo "$match" 1>&2
    echo "$match"
  fi
  [ $tty_echo -eq 1 ] && stty echo
  [ "x$r" = "xy" ] && return 0 || return 1
}

fn_next_file() {
  file="$1"
  delim="${2:-"_"}"
  suffix="${3:-""}"
  [[ -n "$suffix" && ${#file} -gt ${#suffix} && \
        "x${file:$((${#file}-${#suffix}))}" == "x$suffix" ]] && file="${file:0:$((${#file}-${#suffix}))}"
  if [ -e "${file}${suffix}" ]; then
    num="$(echo "$file" | sed -n 's/.*'"$delim"'\([0-9]*\)\('"$suffix"'\)\?$/\1/p')"
    [ "x$num" = "x" ] && num=2 || file="${file:0:$((${#file}-${#delim}-${#num}))}"
    while [ -e "${file}${delim}${num}${suffix}" ]; do num=$((num+1)); done
    file="${file}${delim}${num}"
  fi
  echo "${file}${suffix}"
}

fn_random() {
  len=${1:-10}; s=""; while [ ${#s} -lt $len ]; do s+="$(head -c10 /dev/urandom | tr -dc '[:alnum:]')"; done; echo "${s:0:$len}";
}

fn_temp() {
  name="$1" && shift
  tmp="${1:-$(dirname $(mktemp -u) 2>/dev/null)}"
  [ -z "$tmp" ] && tmp="$TMP";
  [ -z "$tmp" ] && tmp="$TMPDIR";
  [ -z "$tmp" ] && tmp="$TEMP";
  [ -z "$tmp" ] && tmp="/tmp";
  mkdir -p "$tmp" 2>/dev/null
  [ $? -ne 0 ] && echo "[error] failed to set temp storage" 1>&2 && return 1
  f="$tmp/$name.$(fn_random 10)"
  while [ -e "$f" ]; do f="$tmp/$name.$(fn_random 10)"; done
  echo "$f"
}

fn_temp_file() {
  tmp=$(fn_temp "$@")
  res=$?
  [ $res -ne 0 ] && return $res
  touch "$tmp"
  echo "$tmp"
}

fn_temp_dir() {
  tmp=$(fn_temp "$@")
  res=$?
  [ $res -ne 0 ] && return $res
  mkdir "$tmp"
  echo "$tmp"
}

fn_escape() {
  # escape reserved characters
  type="$1" && shift
  exp="$1" && shift
  declare escape
  case "$type" in
    "space") escape="$ESCAPE_SPACE" ;;
    "path") escape="$ESCAPE_PATH" ;;
    "bre") escape="$ESCAPE_BRE" ;;
    "ere") escape="$ESCAPE_ERE" ;;
    "perl") escape="$ESCAPE_PERL" ;;
    "sed") escape="$ESCAPE_SED" ;;
    "awk") escape="$ESCAPE_AWK" ;;
    *) echo "[error] unsupported escape type" 1>&2 && return 1
  esac
  [ $DEBUG -ge 3 ] && echo "[debug] raw expression: '$exp', $type protected chars: '$escape'" 1>&2
  exp="$(echo "$exp" | sed 's/\(['"$escape"']\)/\\\1/g')"
  [ $DEBUG -ge 3 ] && echo "[debug] protected expression: '$exp'" 1>&2
  echo "$exp"
}

fn_path_resolve() {
  target="$1"
  # home
  [ -n "$(echo "$target" | sed -n '/^~/p')" ] &&\
    target="$(echo "$target" | sed 's/^~/'"$(fn_escape "sed" "$HOME")"'/')"
  echo "$target"
}

fn_path_safe() {
  path="$1" && shift
  path="$(fn_escape "path" "$path")"
  transforms="/=_"
  IFS="|" kvs=($(echo "$transforms")); IFS="$IFSORG"
  for kv in "${kvs[@]}"; do
    k="${kv%=*}"
    v="${kv#*=}"
    path="$(echo "$path" | sed 's/['"$k"']/'"$v"'/g')"
  done
  echo "$path"
}

fn_files_compare() {
  [ $DEBUG -ge 5 ] && echo "[debug | fn_files_compare]" 1>&2
  [ $# -lt 2 ] && echo "[error] not enough args" 1>&2 && return 1
  declare base
  declare md5base
  declare md5compare
  declare res
  base="$1" && shift
  [ ! -f "$base" ] && echo "[error] invalid file '$base'" 1>&2 && return 1
  md5base="$(md5sum "$base" | cut -d' ' -f1)"
  res=""
  while [ -n "$1" ]; do
    compare="$1"
    [ ! -f "$base" ] && echo "[error] invalid file '$compare'" 1>&2 && return 1
    md5compare="$(md5sum "$compare" | cut -d' ' -f1)"
    res+="\n$compare\t$([ "x$md5base" = "x$md5compare" ] && echo 1 || echo 0)"
    shift
  done
  echo -e "${res:2}"
}

fn_diff() {
  [ $# -ne 2 ] && echo "[error] expected 'base' and 'compare' args only" && exit 1
  equal=$(fn_files_compare "$1" "$2" | cut -d$'\t' -f2)
  echo $((equal ^= 1))  # bitwise flip to invert
}

fn_reversed_map_values() {
  IFSCUR="$IFS"
  declare del="$1" && shift;
  declare -A reversed_map
  while [ -n "$1" ]; do
    kvp="$1"
    k="${kvp%%${del}*}"
    v="${kvp#*${del}}"
    IFS="$del"; vs=($(echo "$v")); IFS="$IFSCUR"
    for v_ in "${vs[@]}"; do
      existing="${reversed_map["$v_"]}"
      [ -z "$existing" ] && \
        reversed_map["$v_"]="$v_$del$k" || \
        reversed_map["$v_"]="$existing$del$k"
    done
    shift
  done
  for v in "${reversed_map[@]}"; do echo "$v"; done
}

fn_search_set() {
  declare search
  search="$1" && shift
  declare rx
  rx=0
  [[ $# -gt 1 &&
     -n "$(echo "$1" | sed -n '/^[01]$/p')" ]] && \
    rx=$1 && shift
  declare types
  types="f"
  [[ $# -gt 1 &&
     -n "$(echo "$1" | sed -n '/^[fld]\{1,3\}$/p')" ]] && \
    types="$1" && shift
  declare depth
  [[ $# -gt 1 &&
     -n "$(echo "$1" | sed -n '/^[1-9]$/p')" ]] && \
    depth=$1 && shift
  declare -a files
  declare -a files2
  declare -A map
  declare -a bin_args
  if [ -n "$depth" ]; then
    bin_args[${#bin_args[@]}]="-maxdepth"
    bin_args[${#bin_args[@]}]="$depth"
  fi
  if [ $rx -eq 0 ]; then
    bin_args[${#bin_args[@]}]="-iname"
  else
    bin_args[${#bin_args[@]}]="-iregex"
  fi
  bin_args[${#bin_args[@]}]="$search"
  l=0
  bin_args[${#bin_args[@]}]="("
  while [ $l -lt ${#types} ]; do
    [ $l -gt 0 ] && \
      bin_args[${#bin_args[@]}]="-o"
    bin_args[${#bin_args[@]}]="-type"
    bin_args[${#bin_args[@]}]="${types:$l:1}"
    l=$((l + 1))
  done
  bin_args[${#bin_args[@]}]=")"
  while [ -n "$1" ]; do
    t="$(fn_path_resolve "$1")"  # resolve target
    [ $DEBUG -ge 1 ] && echo "[debug] searching target: '$t'" 1>&2
    if [ -e "$t" ]; then
      if [ -f "$t" ]; then
        files2=("$t")
      else
        IFS=$'\n'; files2=($(find "$t" "${bin_args[@]}")); IFS="$IFSORG"
      fi
      for f in "${files2[@]}"; do
        [ -n "${map["$f"]}" ] && continue  # no dupes
        map["$f"]=1
        files[${#files[@]}]="$f"
      done
    elif [ $DEBUG -ge 1 ]; then
      echo "[debug] target '$t' invalid / no longer exists, ignoring" 1>&2
    fi
    shift
  done
  # push
  for f in "${files[@]}"; do echo "$f"; done
}
