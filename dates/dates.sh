#!/bin/bash

IFS_ORG="$IFS"
DEBUG=${DEBUG:-1}

c_up=$'\u21e7' #$'\u2191'
c_down=$'\u21e9' #$'\u2193'
c_left=$'\u21e6' #$'\u2190'
c_right=$'\u21e8' #$'\u2192'
t_b=$'\033[1m'
t_n=$'\033[0m'
t_hlclr=$'\033[0;31m'
t_nclr=$'\033[m'

declare -A datepart_size_map
datepart_size_map['S']=1
datepart_size_map['M']=60
datepart_size_map['H']=$[60*60]
datepart_size_map['d']=$[24*60*60]

fn_dateformat() {
  dt="$1"
  fmt="$2"
  part="$3"
  IFS="%"; parts=(`echo $fmt`); IFS="$IFS_ORG"
  fmt="`echo $fmt | sed 's/\('%$part'\)/'$t_b$t_hlclr'\1'$t_nclr$t_n'/'`"
  dt="`date -d @$dt +"$fmt"`"
  echo "$dt"
}

fn_dateadd() {
  dt=$1
  part=$2
  dir=$3
  size=${datepart_size_map[$part]}
  [ $DEBUG -gt 1 ] && echo "[debug] dt: $dt, part: $part, direction:$dir, size: $size" 1>&2
  if [ "x$size" != "x" ]; then
    echo $[$dt + $dir * $size]
  else
    case $part in
      "b") date -d "`date -d "@$dt" +"%c"` + $dir month" +%s ;;
      "Y") date -d "`date -d "@$dt" +"%c"` + $dir year" +%s ;;
    esac
  fi
}

fn_cycle() {
  num=$1
  max=$2
  dir=$3
  [[ $num -eq 0 && $dir -eq -1 ]] && num=$max
  [ $DEBUG -gt 1 ] && echo "[debug] num: $num, max: $max, direction:$dir" 1>&2
  echo "($num + $dir) % $max" | bc
}

option="edit"
case "$option" in
  "edit")
    dt="$(date -d "${1:-`date "+%c"`}" "+%s")"
    dt_format="%a %d %b %Y, %H:%M:%S %Z (%z)"
    editable=('d' 'b' 'Y' 'H' 'M' 'S')
    last=" "
    hl=0
    cont=1
    while [ 1 ]; do
      echo -en '\033[u\033[s\033[2K\012\033[2K\012\033[2K\012\033[2K\033[u\033[s\012' 1>&2
      dtf="`fn_dateformat $dt "$dt_format" ${editable[$hl]}`"
      echo -ne "$dtf [modify ($t_b$c_up$t_n|$t_b$c_down$t_n) / select part ($t_b$c_left$t_n|$t_b$c_right$t_n) / (c)ancel / e(x)it] $t_b$last$t_n" 1>&2
      [ $cont -ne 1 ] && echo "" 1>&2 && break

      retry=1
      escape=0
      while [ $retry -eq 1 ]; do
        read -s -n 1 res
        case $res in
          $'\e') escape=1 ;;
          A) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$c_up"; dt=`fn_dateadd $dt ${editable[$hl]} 1` ;;
          B) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$c_down"; dt=`fn_dateadd $dt ${editable[$hl]} -1` ;;
          D) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$c_left"; hl=`fn_cycle $hl ${#editable[@]} -1` ;;
          C) if [ $escape -eq 0 ]; then retry=0; aborted=1; update=0; last="c"; else escape=0; retry=0; last="$c_right"; hl=`fn_cycle $hl ${#editable[@]} 1`; fi ;;
          "x"|"X") retry=0; cont=0; last="x" ;;
          "c") retry=0; aborted=1; cont=0; last="c" ;;
        esac
      done
    done
    [ $last == "x" ] && echo "$dt"
    ;;
esac

