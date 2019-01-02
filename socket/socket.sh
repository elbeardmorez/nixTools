#!/bin/sh

SERVER=${SERVER:-localhost}
SERVER_TIMEOUT=${SERVER_TIMEOUT:-60}
PORT=${PORT:-666}
RETRIES=10

direction="out"

[ "x$(echo "$1" | sed -n '/\(in\|out\)/p')" != "x" ] && direction="$1" && shift

case "$direction" in
  "in")
    # server side
    args=("--listen" "--local-port=$PORT")
    persistent=0
    if [ "$#" -gt 0 ]; then
      while [ -n "$1" ]; do
        case "$1" in
          "-ps"|"--persistent") persistent=1 ;;
          *) echo "[user] unrecognised option arg '$1', dropped"
        esac
        shift
      done
    fi
    [ $persistent -eq 0 ] && args[${#args}]="--wait=$SERVER_TIMEOUT"
    echo [info]$([ $persistent -eq 1 ] && echo " persistent") socket opened
    while [ 1 == 1 ]; do
      nc "${args[@]}" > socket
      size=`du -h socket | cut -d'	' -f1`
      if [ "$size" != "0" ]; then
        echo "[info] $size bytes dumped"
        mv socket data
        [ $persistent -eq 0 ] && exit 0
      else
        # non persistent mode only
        echo [info[ socket closed
        exit 0
      fi
    done
    ;;
  "out")
    # client side
    declare -a files
    if [ "$#" -gt 0 ]; then
      while [ -n "$1" ]; do
        case "$1" in
          "-s"|"--server") shift && SERVER="$1" ;;
          "-r"|"--retries") shift && RETRIES="$1" ;;
          *)
            if [ -f "$1" ]; then
              files[${#files[@]}]="$1"
            else
              echo "[user] invalid file specified '$1', ignoring"
            fi
        esac
        shift
      done
    fi
    [ ${#files[@]} -eq 0 ] && echo "[error] no push data" && exit 1
    echo "[user] pushing ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s") to '$SERVER:$PORT'"
    for f in "${files[@]}"; do
      nc -c $SERVER $PORT < "$f"
      if [ $? -ne 0 ]; then
        echo "[info] failed to push file '$f', retrying"
        success=0
        for x in `seq 1 1 $RETRIES`; do
          nc -c $SERVER $PORT < "$f"
          [ $? -eq 0 ] && success=1 && echo "[info] success on retry attempt ${x}" && break
        done
        [ $success -eq 0 ] && echo "[error] pushing data failed, check server side process" && exit 1
      fi
    done
    ;;
esac
