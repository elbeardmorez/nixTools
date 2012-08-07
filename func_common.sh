#!/bin/sh

function tempfile()
{
  if [ ! -d /tmp ]; then
    mkdir /tmp
    chmod -R 0777 /tmp
  fi  
  file=/tmp/$RANDOM$RANDOM
  while [ -e $file ]; do
    file=/tmp/$RANDOM$RANDOM
  done
  touch $file
  echo $file
}
