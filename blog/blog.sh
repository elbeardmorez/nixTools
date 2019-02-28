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
"
}

fn_input_data() {
  type="$1"
  echo -n "$type [enter]: " 1>&2
  read
  echo ""
  echo "$REPLY"
}

fn_output_data() {
  var="$1" && shift
  data="$@"
  echo "'$var': '${data[*]}'" >> "$f_entry"
}

fn_read_data() {
  var="$1" && shift
  entry="${1:-$f_entry}"
  data=$(awk '
BEGIN { data = ""; search = "'"$var"'"; matchx = 0; rx = "^'\''"search"'\'':" };
{
  if ($0 ~ rx) {
    matchx=1; data = substr($0, length(search)+4);
  } else if (matchx == 1) {
    if ($0 ~ /^'\''[a-zA-z0-9_]+'\'': /)
      matchx = 0;
    else
      data = data"\n"$0;
  }
}
END { gsub(/^[ '\'']*/,"",data); gsub(/[ '\'']*$/,"",data); print data;}' < "$entry")
  echo "$data"
}

fn_publish() {
  dt="$1"
  title="$2"
  [ -z "$(echo "$dt" | sed -n '/^[0-9]\+$/p')" ] && dt="$(date -d "$dt" "+%s")"
  title="$(echo "$title"| tr " " ".")"
  [ ! -d "$published" ] && mkdir -p $published
    cp $f_entry "$published/${dt}_${title}"
}

option=new
if [ $# -gt 0 ]; then
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [ -n "$(echo "$arg" | sed -n '/^\(h\|help\|new\|publish\|mod\)$/p')" ] && option="$arg" && shift
fi

case "$option" in
  "h"|"help")
    help && exit
    ;;

  "new")
    rm "$f_entry" 2>/dev/null
    rm "$f_content" 2>/dev/null
    dt_created=$(date +"%s")
    fn_output_data "date created" "$(date -d "@$dt_created" +"%d%b%Y %H:%M:%S")"
    title="$(fn_input_data "title")"
    fn_output_data "title" "$title"
    echo "edit content:"
    sleep 2
    $EDITOR "$f_content"
    fn_output_data "content" "$(cat $f_content)"
    fnDecision "publish?" >/dev/null && fn_publish "$dt_created" "$title"
    ;;

  "publish")
    dt_created="$(fn_read_data "date created")"
    title="$(fn_read_data "title")"
    fnDecision "publish?" >/dev/null && fn_publish "$dt_created" "$title"
    ;;

  "mod")
    # find entry
    search="$1"
    search=$(echo "$search" | tr " " ".")
    IFS=$'\n'; matches=($(grep -rl "'title':.*$(fn_rx_escape "grep" "$search").*" "$published")); IFS="$IFSORG"
    [ ${#matches[@]} -ne 1 ] && echo "[error] couldn't find unique blog entry using search term '$search'" && exit 1
    echo "[info] matched entry '${match[0]}'"
    mv "${matches[0]}" "$f_entry.tmp"

    # edit title
    sed -n '/^'\'"date created"\''/p' "$f_entry.tmp" > "$f_entry"
    res=$(fnDecision "edit title?" "ynx")
    [ "x$res" = "xx" ] && exit 0
    [ "x$res" = "xn" ] &&\
      fn_output_data "title" "$(fn_read_data "title" "$f_entry.tmp")"
    [ "x$res" = "xy" ] &&\
      title="$(fn_input_data "new title")" &&\
      fn_output_data "title" "$title"

    # edit content
    res="$(fnDecision "edit content?" "ynx")"
    [ "x$res" = "xx" ] && exit 0
    [ "x$res" = "xn" ] &&\
      fn_output_data "content" "$(fn_read_data "content" "$f_entry.tmp")"
    [ "x$res" = "xy" ] &&\
      echo "$(fn_input_data "content")" > $f_content &&\
      $EDITOR $f_content &&\
      fn_output_data "content" "$(cat $f_content)"

    # publish
    dt_created="$(fn_read_data "date created" "$f_entry.tmp")"
    title="$(fn_read_data "title" "$f_entry.tmp")"
    fnDecision "publish?" >/dev/null && fn_publish "$dt_created" "$title"
    rm $f_entry.tmp
    ;;

  *)
    echo "[error] unsupported option '$option'"
    ;;
esac
