#!/bin/sh

SCRIPTNAME=${0##*/}

# constants
pi=$(echo "scale=10; 4*a(1)" | bc -l)
# functions
abs="define abs(x) { if (x<0) { x = -x }; return x };"
gt="define gt(x,y) { if(x>y) return 1 else return -1}; scale=0"
ge="define ge(x,y) { if(x>=y) return 1 else return -1}; scale=0"
lt="define lt(x,y) { if(x<y) return 1 else return -1}; scale=0"
le="define le(x,y) { if(x<=y) return 1 else return -1}; scale=0"
max="define max(x,y) { if(x>y) return x else return y}; scale=0"
min="define min(x,y) { if(x<y) return x else return y}; scale=0"
factorial="define factorial(n) { if (n == 0) return(1); return(n * factorial(n - 1)); }"

# params
DEBUG=0
[ $# -gt 0 ] && [ "x$1" == "xdebug" ] && DEBUG=1 && shift
[ ! $# -gt 0 ] && echo error: not enough args && exit 1
funcs=

# base convertion
#echo "16 i 2 o C2 p" | dc
#echo "ibase=16; obase=2; C2" | bc
base=
[ $# -gt 0 ] && [ "x$1" == "xh2b" ] && base="obase=2; ibase=16" && shift && scale="" && bCase=1
[ $# -gt 0 ] && [ "x$1" == "xb2h" ] && base="obase=16; ibase=2" && shift && scale=""
[ $# -gt 0 ] && [ "x$1" == "xh2d" ] && base="ibase=16" && shift && scale="" && bCase=1
[ $# -gt 0 ] && [ "x$1" == "xd2h" ] && base="obase=16" && shift && scale=""
[ $# -gt 0 ] && [ "x$1" == "xd2b" ] && base="obase=2" && shift && scale=""
[ $# -gt 0 ] && [ "x$1" == "xb2d" ] && base="ibase=2" && shift && scale=""

# parse expression for bash variables. don't attempt global variable
# replacement, functions yes
exp="$1"
l=1
while [ "x$(echo "$exp" | sed -n '/[^\]*\$/p')" != "x" ]; do
  var=$(echo "$exp" | sed -n 's|^[^\]*\$\([a-zA-Z0-9_]\+\).*$|\1|p')
  var2="${!var}"
  if [[ ${#var2} -ge 6 && "${var2:0:6}" == "define" ]]; then
    # add to function list and strip all instances
    funcs=$(echo -e "$funcs$var2\n")
    exp=$(echo "$exp" | sed 's|'\$$var'|'$var'|g')
  else
    # replace variable
    exp=$(echo "$exp" | sed 's|'\$$var'|'$var2'|')
  fi
done
shift
[ $# -gt 0 ] && scale=$1 && shift

unit=$(echo "$exp" | sed -n 's/.*\(£\|\$\|k\).*/\1/p')
if [ ! "$unit" == "x" ]; then exp=$(echo "$exp" | sed 's/\(\\£\|\\\$\|\\k\)//g' | sed 's/\(£\|\$\|k\)//g'); fi
[ $bCase ] && exp="$(echo "$exp" | awk '{print toupper($0);}')"

# add required function definitions
[ "$funcs" ] && exp="$funcs; $exp"
# add required base conversion
[ "$base" ] &&  exp="$base; $exp"

# generic fixes for expressions. remove superfluous '+'
exp=$(echo "$exp" | sed 's/^+\|\((\)+/\1/g')

# calc
res=$(echo -e "$exp" | bc -l)

# override scale?
scale2="$(echo "$exp" | sed -n 's|^.*scale=\([0-9]\+\).*$|\1|p')"
[ "x$scale2" != "x" ] && scale=$scale2

# log
[ $DEBUG -gt 0 ] && echo "[debug] scale: '$scale', exp: '$exp', unit: '$unit'"

[ $scale ] && echo $unit$(echo "scale=${scale:-2};$res/1" | bc) || echo "$res"
