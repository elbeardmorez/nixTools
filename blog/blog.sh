#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"

published=$HOME/docs/blogging
f_entry=/tmp/blog_.entry
f_content=/tmp/blog_.content

help() {
  echo -e "\nSYNTAX: $SCRIPTNAME [OPTION [OPTIONARGS]]
\nwhere OPTION can be:\n
  h, help  : this help information
  new  : creates a new blog entry
  publish  : (re)build and push temp data to 'publshed' target
  mod [SEARCH]  : modify current unpublished item or a published item
                  via title search on SEARCH
  list  : list published entries
"
}

fn_sample() {
  max="$1" && shift
  data="$@"
  truncated=0
  len=${#data}
  [ $len -gt $max ] && len=$max && truncated=1
  sample="$(echo "${data:0:$len}" | awk 1 ORS='\\n' | awk '{gsub(/\\n$/,""); print}' IRS='' ORS='')"
  echo "$sample$([ $truncated -eq 1 ] && echo "..")"
}

fn_input_data() {
  declare type
  declare prompt
  declare data
  type="$1" && shift
  prompt="$1" && shift
  [ $# -gt 0 ] && data="$@"
  case "$type" in
    "single_line")
      echo -n "$prompt [enter]: " 1>&2
      fn_edit_line "$data"
      ;;
    "multi_line")
      echo -n "$prompt: " 1>&2
      [ -n "$data" ] &&\
        echo -n "$(fn_sample 50 "$data")" 1>&2 &&\
        echo -e "$data" > $f_content
      sleep 1
      $EDITOR "$f_content" 1>/dev/tty
      echo -e "[2K[A" 1>&2 # reset line
      data="$(cat $f_content)"
      echo -n "$prompt: " 1>&2
      [ -n "$data" ] &&\
        echo -n "$(fn_sample 50 "$data")" 1>&2
      echo "" 1>&2
      echo -e "$data"
      ;;
  esac
}

fn_input_line() {
  fn_input_data "single_line" "$@"
}

fn_input_lines() {
  fn_input_data "multi_line" "$@"
}

fn_write_data() {
  var="$1" && shift
  target="$1" && shift
  data="$@"
  current="$(fn_read_data "$var" "$target")"
  if [ -z "$current" ]; then
    # add entry
    echo "'$var': '${data[*]}'" >> "$target"
  else
    # overwrite entry
    current="'$var': '$current'"
    IFS=$'\n'; lines=($(echo -e "$current")); IFS="$IFSORG"
    first="$(fn_rx_escape "awk" "${lines[0]}")"
    last="$(fn_rx_escape "awk" "${lines[$((${#lines[@]}-1))]}")"
    update="'$var': '$data'"
    awk -v update="$update" -v first="$first" -v last="$last" '
BEGIN {data=""; matchx=0; rx_first="^"first"$"; rx_last="^"last"$"};
{
  if ($0 ~ rx_first) {
    matchx=1; data=data"\n"update;
  }
  if ($0 ~ rx_last) {
    matchx=0;
  } else if (matchx == 0) {
    data=data"\n"$0;
  }
}
END { gsub(/^\n/,"",data); print data}' < "$target" > "$target.tmp"
    check="$(fn_read_data "$var" "$target.tmp")"
    [ "x$check" != "x$data" ] && \
      echo "[error] couldn't validate data write for '$var'" && exit 1
    mv "$target.tmp" "$target"
  fi
}

fn_read_data() {
  var="$1" && shift
  target="$1"
  data=$(awk -v search="$var" '
BEGIN {data=""; matchx=0; rx="^'\''"search"'\'':"};
{
  if ($0 ~ rx) {
    matchx=1; data=substr($0, length(search)+4);
  } else if (matchx == 1) {
    if ($0 ~ /^'\''[a-zA-z0-9_]+'\'': /)
      matchx=0;
    else
      data=data"\n"$0;
  }
}
END {gsub(/^[ ]*'\''/,"",data); gsub(/'\''[ ]*$/,"",data); print data}' < "$target")
  echo "$data"
}

fn_publish() {
  target="$1"
  dt="$(fn_read_data "date created" "$target")"
  title="$(fn_read_data "title" "$target")"
  [ -z "$(echo "$dt" | sed -n '/^[0-9]\+$/p')" ] && dt="$(date -d "$dt" "+%s")"
  title="$(echo "$title"| tr " " ".")"
  [ ! -d "$published" ] && mkdir -p "$published"
  cp "$target" "$published/${dt}_${title}"
  return $?
}

option=new
if [ $# -gt 0 ]; then
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [ -n "$(echo "$arg" | sed -n '/^\(h\|help\|new\|publish\|mod\|list\)$/p')" ] && option="$arg" && shift
fi

case "$option" in
  "h"|"help")
    help && exit
    ;;

  "new")
    rm "$f_entry" 2>/dev/null
    rm "$f_content" 2>/dev/null
    touch "$f_entry"
    touch "$f_content"
    fn_write_data "date created" "$f_entry" "$(date +"%d%b%Y %H:%M:%S")"
    fn_write_data "title" "$f_entry" "$(fn_input_line "title")"
    fn_write_data "content" "$f_entry" "$(fn_input_lines "content")"
    fn_decision "publish?" >/dev/null &&\
      fn_publish "$f_entry" && rm "$f_entry"
    ;;

  "publish")
    fn_publish "$f_entry" && rm "$f_entry"
    ;;

  "mod")
    if [ $# -gt 0 ]; then
      # target a published entry
      search="$1"
      search=$(echo "$search" | tr " " ".")
      IFS=$'\n'; matches=($(grep -rl "'title':.*$(fn_rx_escape "grep" "$search").*" "$published")); IFS="$IFSORG"
      [ ${#matches[@]} -ne 1 ] && echo "[error] couldn't find unique blog entry using search term '$search'" && exit 1
      echo "[info] targeting matched entry '${matches[0]}'"
      # move original
      mv "${matches[0]}" "$f_entry"
      # edit temp version
      cp "$f_entry" "$f_entry.tmp"
    else
      echo "[info] targeting unpublished entry'"
    fi

    # edit title
    data="$(fn_read_data "title" "$f_entry.tmp")"
    res=$(fn_decision "edit title$([ -n "$data" ] && echo " [$(fn_sample 50 "$data")]")?" "ynx")
    [ "x$res" = "xx" ] && exit 0
    [ "x$res" = "xy" ] &&\
      fn_write_data "title" "$f_entry.tmp" "$(fn_input_line "title" "$data")"

    # edit content
    data="$(fn_read_data "content" "$f_entry.tmp")"
    res="$(fn_decision "edit content$([ -n "$data" ] && echo " [$(fn_sample 50 "$data")]")?" "ynx")"
    [ "x$res" = "xx" ] && exit 0
    [ "x$res" = "xy" ] &&\
      fn_write_data "content" "$f_entry.tmp" "$(fn_input_lines "content" "$data")"

    # modified?
    diff=$(fn_diff "$f_entry.tmp" "$f_entry")
    [ $DEBUG -ge 1 ] && echo "[debug] entry$([ $diff -eq 0 ] && echo " not") modified"
    [ $diff -eq 1 ] && fn_write_data "date modified" "$f_entry.tmp" "$(date +"%d%b%Y %H:%M:%S")"

    # overwrite original with updated
    mv "$f_entry.tmp" "$f_entry"

    # publish
    fn_decision "publish?" >/dev/null &&\
      fn_publish "$f_entry" && rm "$f_entry"
    ;;

  "list")
    IFS=$'\n'; files=($(grep -rl "'title':.*" "$published")); IFS="$IFSORG"
    tb=""
    l=1
    for f in "${files[@]}"; do
      dt="$(sed -n 's/'\''date created'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
      title="$(sed -n 's/'\''title'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
      tb+="\n[$l]\t$c_red$title$c_off\t$dt\t$f"
      l=$(($l+1))
    done
    echo "# published entries"
    echo -e "${tb:2}" | column -t -s$'\t'
    ;;

  *)
    echo "[error] unsupported option '$option'"
    ;;
esac
