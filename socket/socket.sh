#!/bin/sh

SCRIPTNAME=${0##*/}

# compatibility
if [ -n "$BASH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-n1")
elif [ -n "$ZSH_VERSION" ]; then
  CMDARGS_READ_SINGLECHAR=("-s" "-k1")
  setopt KSH_ARRAYS
fi

SERVER=${SERVER:-localhost}
SERVER_TIMEOUT=${SERVER_TIMEOUT:-60}
PORT=${PORT:-666}
RETRIES=10

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

  out [ARGS] [DATA [DATA2 ..]]  : (default) client side socket
                                  setup for netcat
    where ARGS can be:

    -s, --server ADDRESS  : specify the target server address
                            (default: localhost)
    -r, --retries COUNT  : set the number retries when a push fails
                           (default: 10)
    -rd, --retry-delay SECONDS  : period to wait between retries
                                  (default: 0.1)
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

fnNextFile() {
  file=$1
  delim="${2:-"_"}"
  if [ -e "$file" ]; then
    postfix="$(echo "$file" | sed -n 's/.*_\([0-9]*\)$/\1/p')"
    if [[ "x$postfix" == "x" ]]; then
      file="${file}${delim}2"
    else
      file="${file:0:$((${#file} - ${#postfix} - 1))}"
      while [ -e ${file}${delim}${postfix} ]; do postfix=$((postfix + 1)); done
      file="${file}${delim}${postfix}"
    fi
  fi
  echo $file
}

fnSend() {
  d="$1"
  verbose=${2:-1}
  raw=$([ -e "$d" ] && echo 0 || echo 1)
  [ $raw -eq 0 ] && (tar --label="socket_" -c "$d" | nc -c $SERVER $PORT) \
                 || (echo "$d" | nc -c $SERVER $PORT)
  res=$?
  [[ $res -ne 0 && $verbose -eq 1 ]] &&
    echo "[info] failed to push $([ $raw -eq 1 ] && echo "data" || echo "file") '$d'"
  return $res
}

fnClean() {
  file="$1"
  IFS=$'\n'; files=($(find . -regex '.*/data\(\_[0-9]+\)?$')); IFS="$IFSORG"
  if [ ${#files[@]} -gt 0 ]; then
    echo -n "[user] default cleaning, purge ${#files[@]} blob$([ ${#files[@]} -ne 1 ] && echo "s")? [y/n]: "
    while [ 1 -eq 1 ]; do
      read ${CMDARGS_READ_SINGLECHAR[@]}
      case "$REPLY" in
        "y"|"Y")
          echo "$REPLY"
          for f in "${files[@]}"; do rm "$f"; done
          break
          ;;
        "n"|"N")
          echo $REPLY
          break
          ;;
      esac
    done
  fi
}

fnProcess() {
  direction="$1" && shift

  case "$direction" in
    "in")
      # server side
      args=("--listen" "--local-port=$PORT")
      persistent=0
      clean=1
      if [ "$#" -gt 0 ]; then
        while [ -n "$1" ]; do
          case "$1" in
            "-ps"|"--persistent") persistent=1 ;;
            "-nc"|"--noclean") clean=0 ;;
            *) echo "[user] unrecognised option arg '$1', dropped"
          esac
          shift
        done
      fi
      [ $persistent -eq 0 ] && args[${#args}]="--wait=$SERVER_TIMEOUT"
      file="data"
      [ $clean -eq 1 ] && fnClean "$file"
      echo "[info]$([ $persistent -eq 1 ] && echo " persistent") socket opened"
      while [[ 1 == 1 ]]; do
        nc "${args[@]}" > socket
        size=`du -h socket | cut -d'	' -f1`
        if [ "$size" != "0" ]; then
          file=$(fnNextFile $file "_")
          mv socket $file
          echo "[info] $size bytes dumped to '$file'"
          if [[ "x$(file --brief --mime-type "$file")" == "xapplication/x-tar" ]]; then
            # socket_ archive?
            [[ "x$(tar --test-label -f "$file")" == "xsocket_" ]] && \
              echo "[info] exploding archive in background" && \
              (tar -xvf "$file" && rm $file) &
          fi
          [ $persistent -eq 0 ] && exit 0
        else
          # non persistent mode only
          echo "[info] socket closed"
          exit 0
        fi
      done
      ;;
    "out")
      # client side
      raw=0
      retry_delay=0.1
      declare -a data
      if [ "$#" -gt 0 ]; then
        while [ -n "$1" ]; do
          case "$1" in
            "-s"|"--server") shift && SERVER="$1" ;;
            "-r"|"--retries") shift && RETRIES="$1" ;;
            "-rd"|"--retry-delay") shift && retry_delay=$1 ;;
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
      [ ${#data[@]} -eq 0 ] && echo "[error] no push data" && exit 1
      echo "[user] pushing ${#data[@]} blob$([ ${#data[@]} -ne 1 ] && echo "s") to '$SERVER:$PORT'"
      for d in "${data[@]}"; do
        fnSend "$d"
        if [ $? -ne 0 ]; then
          success=0
          for x in `seq 1 1 $RETRIES`; do
            sleep $retry_delay
            fnSend "$d" 0 # quietly
            [ $? -eq 0 ] && success=1 && echo "[info] success on retry attempt ${x}" && break
          done
           [ $success -eq 0 ] && echo "[error] pushing data failed, check server side process" && exit 1
        fi
        sleep 0.1
      done
      ;;
  esac
}

option="out"
[[ "x$(echo "$1" | sed -n '/\(in\|out\|help\)/p')" != "x" ]] && option="$1" && shift
case $option in
  "in"|"out") fnProcess $option "$@" ;;
  "help") help ;;
esac
