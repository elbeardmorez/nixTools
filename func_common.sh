#!/bin/sh

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  setopt KSH_ARRAYS
fi

# constants
IFSORG="$IFS"
ESCAPE_SED='].[|/-'
c_off='\033[0m'
c_red='\033[0;31m'

fnEditLine() {
  var="$1"
  if [ -n "$BASH_VERSION" ]; then
    read -e -i "$var" var
  elif [ -n "$ZSH_VERSION" ]; then
    var="$(zsh -i -c 'var="'"$var"'"; vared var; echo "$var"')"
  fi
  echo "$var"
}

fnDecision() {
  IFS='|'; keys=($(echo "${1:-y|n}")); IFS="$IFSORG"
  while [ 1 -eq 1 ]; do
    read "${CMDARGS_READ_SINGLECHAR[@]}"
    r="$(echo "$REPLY" | tr '[A-Z]' '[a-z]')"
    match=0
    for k in "${keys[@]}"; do
      [ "x$k" = "x$r" ] && match=1 && echo "$r" 1>&2 && echo "$r" && break;
    done
    [ $match -eq 1 ] && break
  done
  [ "x$r" = "xy" ] && return 0 || return 1
}

fnNextFile() {
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

fnRandom() {
  len=${1:-10}; s=""; while [ ${#s} -lt $len ]; do s+="$(head -c10 /dev/random | tr -dc '[[:alnum:]]')"; done; echo "${s:0:$len}";
}

fnTemp() {
  name="$1" && shift
  tmp="${1:-$(dirname $(mktemp -u) 2>/dev/null)}"
  [ -z "$tmp" ] && tmp="$TMP";
  [ -z "$tmp" ] && tmp="$TMPDIR";
  [ -z "$tmp" ] && tmp="$TEMP";
  [ -z "$tmp" ] && tmp="/tmp";
  mkdir -p "$tmp" 2>/dev/null
  [ $? -ne 0 ] && echo "[error] failed to set temp storage" 1>&2 && return 1
  f="$tmp/$name.$(fnRandom 10)"
  while [ -e "$f" ]; do f="$tmp/$name.$(fnRandom 10)"; done
  echo "$f"
}

fnTempFile() {
  tmp=$(fnTemp "$@")
  res=$?
  [ $res -ne 0 ] && return $res
  touch "$tmp"
  echo "$tmp"
}

fnTempDir() {
  tmp=$(fnTemp "$@")
  res=$?
  [ $res -ne 0 ] && return $res
  mkdir "$tmp"
  echo "$tmp"
}

fnRegexp() {
  # escape reserved characters
  exp="$1" && shift
  [ $DEBUG -ge 3 ] && echo "[debug] raw expression: '$exp', sed protected chars: '$ESCAPE_SED'" 1>&2
  exp="$(echo "$exp" | sed 's/\(['$ESCAPE_SED']\)/\\\1/g')"
  [ $DEBUG -ge 3 ] && echo "[debug] protected expression: '$exp'" 1>&2
  echo "$exp"
}
