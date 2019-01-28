#!/bin/sh

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  setopt KSH_ARRAYS
fi

# constants
c_off='\033[0m'
c_red='\033[0;31m'

fnDecision() {
  while [ 1 -eq 1 ]; do
    read "${CMDARGS_READ_SINGLECHAR[@]}"
    case "$REPLY" in
      "y"|"Y") echo "$REPLY" 1>&2; echo 1; break ;;
      "n"|"N") echo "$REPLY" 1>&2; echo 0; break ;;
    esac
  done
}

fnNextFile() {
  file="$1"
  delim="${2:-"_"}"
  if [ -e "$file" ]; then
    postfix="$(echo "$file" | sed -n 's/.*'"$delim"'\([0-9]*\)$/\1/p')"
    if [[ "x$postfix" == "x" ]]; then
      file="${file}${delim}2"
    else
      file="${file:0:$((${#file} - ${#postfix} - 1))}"
      while [ -e "${file}${delim}${postfix}" ]; do postfix=$((postfix + 1)); done
      file="${file}${delim}${postfix}"
    fi
  fi
  echo "$file"
}

fnRandom() {
  len=${1:-10}; s=""; while [ ${#s} -lt $len ]; do s+="$(head -c10 /dev/random | tr -dc '[[:alnum:]]')"; done; echo "${s:0:$len}";
}

fnTempFile() {
  tmp="${1:-$(dirname $(mktemp -u) 2>/dev/null)}"
  [ -z "$tmp" ] && tmp="$TMP";
  [ -z "$tmp" ] && tmp="$TMPDIR";
  [ -z "$tmp" ] && tmp="$TEMP";
  [ -z "$tmp" ] && tmp="/tmp";
  mkdir -p "$tmp"
  [ $? -ne 0 ] && echo "[error] failed to set temp storage" && exit 1
  f="$tmp/$SCRIPTNAME.$(fnRandom 10)"
  while [ -e "$f" ]; do f="$TMP/$SCRIPTNAME.$(fnRandom 10)"; done
  echo "$f"
}
