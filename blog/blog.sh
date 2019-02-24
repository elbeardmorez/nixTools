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
  echo -e "SYNTAX: $SCRIPTNAME [OPTION]
\nwhere OPTION is:
  new      : create a new entry
  publish  : (re)build and push temp data to 'publshed' target
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

fn_publish() {
  dt="$1"
  title="$2"
  title="$(echo "$title"| tr " " ".")"
  [ ! -d "$published" ] && mkdir -p $published
    cp $f_entry "$published/$dt_$title"
}

option=new
[ $# -gt 0 ] && option="$1" && shift

case "$option" in
  "h"|"-h"|"help"|"-help"|"--help")
    help && exit
    ;;

  "new")
    rm "$f_entry" 2>/dev/null
    dt_created=$(date +"%s")
    fn_output_data "date created" "$(date -d "@$dt_created" +"%d%b%Y %H:%M:%S")"
    title="$(fn_input_data "title")"
    fn_output_data "title" "$title"
    echo "edit content:"
    sleep 2
    $EDITOR $f_content
    fn_output_data "content" "$(cat $f_content)"
    fnDecision "publish?" >/dev/null && fn_publish "$dt_created" "$title"
    ;;

  "publish")
    dt_created=$(head -n1 "$f_entry")
    title=$(cat $f_entry | sed -n 's/'\'title\'': \(.*\)/\1/p')
    fnDecision "publish?" >/dev/null && fn_publish "$dt_created" "$title"
    ;;
esac
