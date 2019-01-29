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

ESCAPE_SED='].[|/-'

fnDecision() {
  while [ 1 -eq 1 ]; do
    read "${CMDARGS_READ_SINGLECHAR[@]}"
    case "$REPLY" in
      "y"|"Y") echo "$REPLY" 1>&2; echo 1; break ;;
      "n"|"N") echo "$REPLY" 1>&2; echo 0; break ;;
      "c"|"C") echo "$REPLY" 1>&2; echo -1; break ;;
    esac
  done
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

fnRegexp() {
  # escape reserved characters
  exp="$1" && shift
  [ $DEBUG -ge 2 ] && echo "[debug] raw expression: '$exp', sed protected chars: '$ESCAPE_SED'" 1>&2
  exp="$(echo "$exp" | sed 's/\(['$ESCAPE_SED']\)/\\\1/g')"
  [ $DEBUG -ge 2 ] && echo "[debug] protected expression: '$exp'" 1>&2
  echo "$exp"
}
