#!/bin/sh

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  setopt KSH_ARRAYS
fi

# constants
DEBUG=${DEBUG:-0}
IFSORG="$IFS"
ESCAPE_PATH=')]}{[(/$# '
ESCAPE_GREP='].[*'
ESCAPE_SED='].[/-'
ESCAPE_AWK='.\|[('
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
keychr_maps["$KEY_ARR_U"]="$CHR_ARR_U"
keychr_maps["$KEY_ARR_D"]="$CHR_ARR_D"
keychr_maps["$KEY_ARR_L"]="$CHR_ARR_L"
keychr_maps["$KEY_ARR_R"]="$CHR_ARR_R"

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
  IFS="$optdelim"; options=($(echo "$soptions")); IFS="$IFSORG"
  if [ $optshow -eq 1 ]; then
    soptions=""
    for option in "${options[@]}"; do
      map="${keychr_maps["$option"]}"
      soptions+="$optdelim${CLR_HL}${map:-"$option"}${CLR_OFF}"
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
#  clear stdin
#  read -s -t 0.1 &&\
#    while [ -n "$REPLY" ]; do REPLY="" && read -s -t 0.1; done
  while [ 1 ]; do
    [ $optecho -eq 1 ] && stty echo
    read "${cmd_args[@]}"
    stty -echo
    R="$REPLY"
    [ "x$R" = "x"$'\E' ] && R='\033'
    r="$(echo "$R" | tr '[A-Z]' '[a-z]')"
    map=""
    if [ ${#buffer} -gt 0 ]; then
      for key in "${!keychr_maps[@]}"; do
        buffer_prefix_length=$((${#key}-1))
        if [ $buffer_prefix_length -gt 0 ]; then
          buffer_prefix=""
          [ ${#buffer} -ge $buffer_prefix_length ] &&\
            buffer_prefix="${buffer:$((${#buffer}-$buffer_prefix_length))}"
          [ "x$key" = "x$buffer_prefix$R" ] &&\
            map="$key" && break
        fi
      done
    fi
    match=0
    chr=""
    for option in "${options[@]}"; do
      if [[ -n "$map" && "x$option" == "x$map" ]]; then
        chr="${keychr_maps[$key]}"
        match=1
        break
      elif [[ -z "$map" && "x$option" == "x$r" ]]; then
        chr="$r"
        match=1
        break
      fi
    done
    if [ $match -eq 1 ]; then
      [ $optecho -eq 1 ] && echo "$chr" 1>&2
      echo "$chr"
      break
    fi
    buffer+="$R"
  done
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

fn_rx_escape() {
  # escape reserved characters
  type="$1" && shift
  exp="$1" && shift
  declare escape
  case "$type" in
    "path") escape="$ESCAPE_PATH" ;;
    "grep") escape="$ESCAPE_GREP" ;;
    "sed") escape="$ESCAPE_SED" ;;
    "awk") escape="$ESCAPE_AWK" ;;
    *) echo "[error] unsupported regexp type" 1>&2 && return 1
  esac
  [ $DEBUG -ge 3 ] && echo "[debug] raw expression: '$exp', $type protected chars: '$escape'" 1>&2
  exp="$(echo "$exp" | sed 's/\(['"$escape"']\)/\\\1/g')"
  [ $DEBUG -ge 3 ] && echo "[debug] protected expression: '$exp'" 1>&2
  echo "$exp"
}

fn_resolve() {
  target="$1"
  # home
  [ -n "$(echo "$target" | sed -n '/^~/p')" ] &&\
    target="$(echo "$target" | sed 's/^~/'"$(fn_rx_escape "sed" "$HOME")"'/')"
  echo "$target"
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
