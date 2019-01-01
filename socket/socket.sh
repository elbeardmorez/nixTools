#!/bin/sh

SERVER=${SERVER:-localhost}
PORT=${PORT:-666}

direction="$1" && shift

case "$direction" in
  "in")
    echo [user] socket opened
    while [ 1 == 1 ]; do
      nc -l -p $PORT -w 60 > socket
      size=`du -h socket | cut -d'	' -f1`
      if [ "$size" != "0" ]; then
        echo "$size bytes dumped"
        mv socket data
      else
        echo [user[ socket closed
        exit 0
      fi
      sleep 2
    done
    ;;
  "out")
    file="$1"
    [ ! -f "$file" ] && echo "[error] no push data" && exit 1
    nc $SERVER $PORT < "$file"
    ;;
esac
