#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}

if [ "x$(nc -h 2>&1 | grep '\-c, --close')" != "x" ]; then
  CMDARGS_NC_CLOSE=("-c")
elif [ "x$(nc -h 2>&1 | grep '\-q secs')" != "x" ]; then
  CMDARGS_NC_CLOSE=("-q" 0)
fi

SERVER=${SERVER:-localhost}
SERVER_TIMEOUT=${SERVER_TIMEOUT:-60}
PORT=${PORT:-666}
RETRIES=10
RETRY_DELAY=0.1
DELAY_CLOSE=1
PRESERVE_PATHS=0
SOCKET=""

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTION] [ARGS]\n
where OPTION can be:
  in [ARGS]  : server side socket setup for netcat
    where ARGS can be:
    -ps, --persistent  : leave connection open by default the
                         script exits after the first payload is
                         received
    -nc, --noclean  : don't even ask to delete existing blobs in
                      current directory
    -ls, --local-socket  : open socket in current directory

  out [ARGS] [DATA [DATA2 ..]]  : (default) client side socket
                                  setup for netcat
    where ARGS can be:

    -s, --server ADDRESS  : specify the target server address
                            (default: localhost)
    -r, --retries COUNT  : set the number retries when a push fails
                           (default: 10)
    -pp, --preserve-paths  : don't strip paths from files /
                             directories
    -rd, --retry-delay SECONDS  : period to wait between retries
                                  (default: 0.1)
    -dc, --delay-close SECONDS  : period to wait before allowing
                                  netcat to process EOF and close
                                  its connection (default: 1)
    -a, --any  : process non-file/dir args as valid raw data strings
                 to be push to the server

  and DATA args are either file / directory paths, or raw data (using
  '-a' / '--any' switch)

  environment variables:
  'SERVER' (client)  : as detailed above
  'PORT' (server / client)  : set communication port (default: 666)
  'SERVER_TIMEOUT' (server)  : in non-persistent mode, the server
                               side will automatically terminate after
                               this interval where no packets are
                               received (default: 60)
"
}

fnSend() {
  d="$1"
  raw=$([ -e "$d" ] && echo 0 || echo 1)
  if [ $raw -eq 0 ]; then
    root="." &&
    if [[ -f "$d" && $PRESERVE_PATHS -ne 1 ]]; then
      root="$(dirname "$d")"
      d="$(basename "$d")"
    fi
    (tar --label="socket_" -C $root -c "$d"; sleep $delay_close) | nc ${CMDARGS_NC_CLOSE[@]} $SERVER $PORT
  else
    (echo "$d"; sleep $delay_close) | nc ${CMDARGS_NC_CLOSE[@]} $SERVER $PORT
  fi
  res=$?
  return $res
}

fnClean() {
  file="$1"
  IFS=$'\n'; files=($(find . -regex '.*/'"$file"'\(\_[0-9]+\)?$')); IFS="$IFSORG"
  if [ ${#files[@]} -gt 0 ]; then
    echo -n "[user] default cleaning, purge ${#files[@]} blob$([ ${#files[@]} -ne 1 ] && echo "s")? [y/n]: "
    fnDecision >/dev/null && for f in "${files[@]}"; do rm "$f"; done
  fi
}

fnCleanUp() {
  [ -n $SOCKET ] && [ -e $SOCKET ] && rm $SOCKET >/dev/null 2>&1
}

fnProcess() {
  direction="$1" && shift

  case "$direction" in
    "in")
      # server side
      args=("-l" "-p" $PORT)
      persistent=0
      clean=1
      localsocket=0
      if [ "$#" -gt 0 ]; then
        while [ -n "$1" ]; do
          case "$1" in
            "-ps"|"--persistent") persistent=1 ;;
            "-nc"|"--noclean") clean=0 ;;
            "-ls"|"--local-socket") localsocket=1 ;;
            *) echo "[user] unrecognised option arg '$1', dropped"
          esac
          shift
        done
      fi
      [ $persistent -eq 0 ] && args=("${args[@]}" "-w" $SERVER_TIMEOUT)
      file="data"
      [ $clean -eq 1 ] && fnClean "$file"
      echo "[info]$([ $persistent -eq 1 ] && echo " persistent") socket opened"
      SOCKET="$(fnTempFile "$SCRIPTNAME" "$([ $localsocket -eq 1 ] && echo ".")")"
      [ $? -ne 0 ] && exit 1
      while [[ 1 == 1 ]]; do
        nc "${args[@]}" > "$SOCKET"
        size=`du -h $SOCKET | cut -d'	' -f1`
        if [ "$size" != "0" ]; then
          file=$(fnNextFile $file "_")
          mv "$SOCKET" $file
          echo "[info] $size bytes dumped to '$file'"
          if [[ "x$(file --brief --mime-type "$file")" == "xapplication/x-tar" ]]; then
            # socket_ archive?
            [[ "x$(tar --test-label -f "$file")" == "xsocket_" ]] && \
              echo "[info] exploding archive in background" && \
              (tar -xvf "$file" && rm $file) &
          fi
          [ $persistent -eq 0 ] && break
        else
          echo "[info] socket closed"
          break
        fi
      done
      fnCleanUp
      ;;
    "out")
      # client side
      raw=0
      retry_delay=$RETRY_DELAY
      delay_close=$DELAY_CLOSE
      declare -a data
      if [ "$#" -gt 0 ]; then
        while [ -n "$1" ]; do
          case "$1" in
            "-s"|"--server") shift && SERVER="$1" ;;
            "-r"|"--retries") shift && RETRIES="$1" ;;
            "-pp"|"--preserve-paths") PRESERVE_PATHS=1 ;;
            "-rd"|"--retry-delay") shift && retry_delay=$1 ;;
            "-dc"|"--delay-close") shift && delay_close=$1 ;;
            "-a"|"--any") raw=1 ;;
            *)
              if [[ -e "$1" || "$raw" -eq 1 ]]; then
                data[${#data[@]}]="$1"
              else
                dd="$1"
                [[ ${#dd[@]} -gt 20 ]] && dd="${data:0:20}.."
                echo "[user] invalid file / dir specified. use '-a' / '--any' switch to push '$1' raw. ignoring"
              fi
          esac
          shift
        done
      fi
      [ ${#data[@]} -eq 0 ] && echo "[error] no blobs to published" && exit 1
      echo "[user] pushing ${#data[@]} blob$([ ${#data[@]} -ne 1 ] && echo "s") to '$SERVER:$PORT'"
      for d in "${data[@]}"; do
        success=1
        attempt=1
        blob_type="$([ $raw -eq 1 ] && echo "data" || echo "file")"
        fnSend "$d"
        res=$?
        if [ $res -ne 0 ]; then
          success=0
          for attempt in `seq 2 1 $(($RETRIES+1))`; do
            [ $DEBUG -gt 0 ] && echo "[debug] failed to push $blob_type '$d' [attempt: $(($attempt-1))]"
            sleep $retry_delay
            fnSend "$d"
            res=$?
            [ $res -eq 0 ] && success=1 && break
          done
        fi
        if [ $success -eq 1 ]; then
          echo "[info] success pushing $blob_type '$d'$([ $attempt -gt 1 ] && echo " after $attempt attempts")"
        else
          echo "[info] failed pushing $blob_type '$d' after $attempt attempts, check server side process" && exit 1
        fi
        sleep 0.5
      done
      ;;
  esac
}

option="out"
[ $# -eq 0 ] && help && exit
[[ "x$(echo "$1" | sed -n 's/[-]*\(in\|out\|h\|help\)/\1/p')" != "x" ]] && option="$(echo "$1" | sed 's/^-*//g')" && shift
case $option in
  "in"|"out") fnProcess $option "$@" ;;
  "h"|"help") help ;;
esac
