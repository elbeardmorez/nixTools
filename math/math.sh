#!/bin/sh

SCRIPTNAME=${0##*/}
DEBUG=${DEBUG:-0}

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

fn_search() {
  data="$1" && shift
  search="$1" && shift
  direction=${1:-1}
  echo "$data" | awk -vsearch="$search" -vdirection=$direction '{ idx=index($0, search); if (idx > 0 && direction == -1) idx += length(search) - 1; print idx; }'
}

fn_next_block() {
  data="$1" && shift
  start=$1 && shift
  direction=$1
  echo "$data" | awk -vstep=$direction -vstart=$start \
                     -vlimit="$([ $direction = -1 ] && echo 0 || echo $((${#data} + 1)))" '
BEGIN {
  count=0; mode=-1; idx = -1; idx2 = -1;
}
{
  l = start;
  while (l != limit) {
    c = substr($0, l, 1);
    if (mode == -1) {
      if (c == " ") {
        continue;
      } else if (c == ")" || c == "(") {
        mode = 2; count++;
      } else {
        mode = 1;
      }
    } else {
      if (mode == 2) {
        if (c == ")" || c == "(") {
          if ((c == ")" && step == 1) ||
              (c == "(" && step == -1))
               count--;
          else if ((c == ")" && step == -1) ||
              (c == "(" && step == 1))
               count++;
        }
        if (count == 0) { idx = l + step; break; }
      }
      else if (mode == 1) {
        if (c ~ /[-+ ]/) { idx = l; break; }
      }
    }
    '"$([ $DEBUG -ge 5 ] && \
      echo "print(\"[debug] considered: \"c\", nest:\"count\", limit: \"limit) > \"/dev/stderr\";")"'
    l += step;
  }
  if (idx == -1)
    idx = limit
  print idx;
}'
}

fn_wrap() {
  declare exp; exp="$1" && shift
  declare target; target="$1" && shift
  declare replace; replace="$1" && shift
  declare direction; direction=${1:-1}  # from left or from right, suffix vs prefix

  declare idx; idx="$(fn_search "$exp" "$target" $direction)"
  declare idx2
  while [ $idx -gt 0 ]; do
    idx2=$(fn_next_block "$exp" $((idx + direction * ${#target})) $direction)
    exp="$(echo "$exp" | awk -vtarget="$target" -vreplace="$replace" -vdirection=$direction -vidx=$idx -vidx2=$idx2 '
{
  if (direction == -1) {
    idx_=idx2; idx2=idx; idx=idx_
    print(substr($0, 0, idx)"$factorial("substr($0, idx + 1, idx2 - (idx + length(target)))")"substr($0, idx2 + 1));
  } else {
    print(substr($0, 0, idx - 1)"$factorial("substr($0, (idx + length(target)), idx2 - (idx + length(target)))")"substr($0, idx2));
  }
}')"
    idx="$(fn_search "$exp" "$target")"
  done
  echo "$exp"
}

# process args
declare exp
declare funcs
declare base
declare scale
declare case_

[ $# -eq 0 ] && \
  echo "[error] not enough args" && exit 1

# base convertion
if [ $# -gt 1 ]; then
  case "$1" in
    "h2b") base="obase=2; ibase=16" && shift && scale="" && case_=1 ;;
    "b2h") base="obase=16; ibase=2" && shift && scale="" ;;
    "h2d") base="ibase=16" && shift && scale="" && case_=1 ;;
    "d2h") base="obase=16" && shift && scale="" ;;
    "d2b") base="obase=2" && shift && scale="" ;;
    "b2d") base="ibase=2" && shift && scale="" ;;
  esac
fi

# expression
exp="$1" && shift

# scale
[ $# -gt 0 ] && scale=$1 && shift

# operators
## factorial
exp="$(fn_wrap "$exp" "!" "\$factorial" -1)"
[ $DEBUG -ge 1 ] && echo "[debug] post operators | exp: '$exp'"

# parse expression for functions and shell variables
l=1
while [ -n "$(echo "$exp" | sed -n '/[^\]*\$/p')" ]; do
  var=$(echo "$exp" | sed -n 's|^[^\]*\$\([a-zA-Z0-9_]\+\).*$|\1|p')
  var2="${!var}"
  if [[ ${#var2} -ge 6 && "x${var2:0:6}" == "xdefine" ]]; then
    # add to function definition string and replace all instances
    funcs=$(echo -e "$funcs$var2\n")
    exp=$(echo "$exp" | sed 's|'\$$var'|'$var'|g')
  else
    # replace variable
    exp=$(echo "$exp" | sed 's|'\$$var'|'$var2'|')
  fi
done

# units
unit=$(echo "$exp" | sed -n 's/.*\(£\|\$\|k\).*/\1/p')
[ -n "$unit" ] && \
  exp="$(echo "$exp" | sed 's/\(\\£\|\\\$\|\\k\)//g' | sed 's/\(£\|\$\|k\)//g')"
[[ -n "$case_" && $case_ -eq 1 ]] && \
  exp="$(echo "$exp" | awk '{print toupper($0);}')"

# prefix function definitions
[ "$funcs" ] && exp="$funcs; $exp"
# prefix base conversion
[ "$base" ] &&  exp="$base; $exp"

# generic mods
## remove superfluous '+'
exp="$(echo "$exp" | sed 's/^+\|\((\)+/\1/g')"

# calc
res="$(echo -e "$exp" | bc -l)"

# override scale?
scale2="$(echo "$exp" | sed -n 's|^.*scale=\([0-9]\+\).*$|\1|p')"
[ "x$scale2" != "x" ] && scale=$scale2
[ $DEBUG -gt 0 ] && echo "[debug] scale: '$scale', exp: '$exp', unit: '$unit'"

# result
[ -n "$scale" ] && echo "$unit$(echo "scale=${scale:-2};$res/1" | bc)" || echo "$res"
