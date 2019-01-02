#!/bin/sh

SERVER=${SERVER:-localhost}
SERVER_TIMEOUT=${SERVER_TIMEOUT:-60}
PORT=${PORT:-666}

direction="$1" && shift

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
    file="$1"
    [ ! -f "$file" ] && echo "[error] no push data" && exit 1
    nc -c $SERVER $PORT < "$file"
    ;;
esac
