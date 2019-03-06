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
ESCAPE_GREP='].[*'
ESCAPE_SED='].[|/-'
ESCAPE_AWK='.\|[('
c_off='\033[0m'
c_red='\033[0;31m'

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
  var="$1"
  if [ -n "$BASH_VERSION" ]; then
    read -e -i "$var" var
  elif [ -n "$ZSH_VERSION" ]; then
    var="$(zsh -i -c 'var="'"$var"'"; vared var; echo "$var"')"
  fi
  echo "$var"
}

fn_decision() {
  declare question
  declare soptions
  declare -a options
  [[ $# -gt 1 || -n "$(echo "$1" | sed -n '/?$/p')" ]] && question="$1" && shift
  soptions="${1:-y|n}"
  [ -z "$(echo "$soptions" | sed -n '/|/p')" ] &&\
    soptions="$(echo "$1" | sed 's/\([[:alpha:]]\)/|\1/g;s/^|//')"
  IFS='|'; options=($(echo "$soptions")); IFS="$IFS_ORG"
  [ ! -t 0 ] &&\
    "[error] stdin is not attacted to a suitable input device" 1>&2 && return 1
  [ -n "$question" ] && echo -n "$question [$soptions]: " 1>&2
  while [ 1 -eq 1 ]; do
    read "${CMDARGS_READ_SINGLECHAR[@]}"
    r="$(echo "$REPLY" | tr '[A-Z]' '[a-z]')"
    while [ -n "$REPLY" ]; do REPLY="" && read -t 0.1; done  # clear stdin
    match=0
    for option in "${options[@]}"; do
      [ "x$option" = "x$r" ] && match=1 && echo "$r" 1>&2 && echo "$r" && break;
    done
    [ $match -eq 1 ] && break
  done
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
  len=${1:-10}; s=""; while [ ${#s} -lt $len ]; do s+="$(head -c10 /dev/random | tr -dc '[:alnum:]')"; done; echo "${s:0:$len}";
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
    res+="\n$compare\t$([ "x$md5base" == "x$md5compare" ] && echo 1 || echo 0)"
    shift
  done
  echo -e "${res:2}"
}

fn_diff() {
  [ $# -ne 2 ] && echo "[error] expected 'base' and 'compare' args only" && exit 1
  equal=$(fn_files_compare "$1" "$2" | cut -d$'\t' -f2)
  echo $((equal ^= 1))  # bitwise flip to invert
}
