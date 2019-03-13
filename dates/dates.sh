#!/bin/bash

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

DEBUG=${DEBUG:-0}

declare -A datepart_size_map
datepart_size_map['S']=1
datepart_size_map['M']=60
datepart_size_map['H']=$[60*60]
datepart_size_map['d']=$[24*60*60]

fn_dateformat() {
  dt="$1"
  fmt="$2"
  part="$3"
  IFS="%"; parts=(`echo $fmt`); IFS="$IFSORG"
  fmt="`echo $fmt | sed 's/\('%$part'\)/\'$CLR_HL'\'$CLR_RED'\1\'$CLR_OFF'/'`"
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
      echo -en "${TERM_CLR}"
      dtf="`fn_dateformat $dt "$dt_format" ${editable[$hl]}`"
      echo -ne "$dtf [modify ($CLR_HL$CHR_ARR_U$CLR_OFF|$CLR_HL$CHR_ARR_D$CLR_OFF) / select part ($CLR_HL$CHR_ARR_L$CLR_OFF|$CLR_HL$CHR_ARR_R$CLR_OFF) / (c)ancel / e(x)it] $CLR_HL$last$CLR_OFF" 1>&2
      [ $cont -ne 1 ] && echo "" 1>&2 && break

      retry=1
      escape=0
      while [ $retry -eq 1 ]; do
        read -s -n 1 res
        case $res in
          $'\e') escape=1 ;;
          A) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$CHR_ARR_U"; dt=`fn_dateadd $dt ${editable[$hl]} 1` ;;
          B) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$CHR_ARR_D"; dt=`fn_dateadd $dt ${editable[$hl]} -1` ;;
          D) [ $escape -eq 0 ] && continue; escape=0; retry=0; last="$CHR_ARR_L"; hl=`fn_cycle $hl ${#editable[@]} -1` ;;
          C) if [ $escape -eq 0 ]; then retry=0; aborted=1; update=0; last="c"; else escape=0; retry=0; last="$CHR_ARR_R"; hl=`fn_cycle $hl ${#editable[@]} 1`; fi ;;
          "x"|"X") retry=0; cont=0; last="x" ;;
          "c") retry=0; aborted=1; cont=0; last="c" ;;
        esac
      done
    done
    [ $last = "x" ] && echo "$dt"
    ;;
esac

