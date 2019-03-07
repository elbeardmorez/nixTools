#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"

path_blog_root="$HOME/documents/blog"
published="$path_blog_root/published"
unpublished="$path_blog_root/unpublished"
[ -d "$published" ] || mkdir -p "$published" || exit 1
[ -d "$unpublished" ] || mkdir -p "$published" || exit 1

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
  echo -E "$sample$([ $truncated -eq 1 ] && echo -n "..")"
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
      fn_edit_line "$data" "$prompt [enter]: "
      ;;
    "multi_line")
      echo -n "$prompt: " 1>&2
      declare f
      f="$(fn_temp_file $SCRIPTNAME)"
      [ -n "$data" ] &&\
        echo -E -n "$(fn_sample 50 "$data")" 1>&2 &&\
        echo -e "$data" > "$f"
      sleep 1
      $EDITOR "$f" 1>/dev/tty
      echo -e "$ESC_RST" 1>&2
      data="$(cat "$f")"
      rm "$f"
      echo -E -n "$prompt: " 1>&2
      [ -n "$data" ] &&\
        echo -E -n "$(fn_sample 50 "$data")" 1>&2
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

fn_target() {
  declare target
  [ $# -gt 0 ] && target="$1" && shift
  if [ -f "$target" ]; then
    [ -z "$(grep "'title':.*" "$target")" ] &&\
      echo "[error] invalid target file '$target'" 1>&2 && return 1
  else
    declare path_
    declare search
    declare files
    if [ -d "$target" ]; then
      path_="$target"
    else
      case "$target" in
        "published") path_="$published" ;;
        "unpublished") path_="$unpublished" ;;
        *)
          if [ $# -eq 0 ]; then
            path_="$path_blog_root"
            search="$target"
          else
            echo "[error] invalid target '$target'"
            return 1
          fi
          ;;
      esac
    fi
    [ $# -gt 0 ] && search="$1" && shift
    IFS=$'\n'; files=($(grep -rl "'title':.*$([ -n "$search" ] && echo "$(fn_rx_escape "grep" "$search").*")" "$path_")); IFS="$IFSORG"
    if [ ${#files[@]} -eq 0 ]; then
      echo "[info] no blog entr$([ -n "$search" ] && echo "y found using search term '$search'" || echo "ies found")" 1>&2 && return 1
    elif [ ${#files[@]} -eq 1 ]; then
      target="${files[0]}"
    elif [ ${#files[@]} -gt 1 ]; then
      fn_list "$target" "${files[@]}" 1>&2
      declare res
      while [ 1 ]; do
        res=$(fn_input_line "[user] select target (1-${#files[@]}) or e(x)it")
        [ "x$res" = "xx" ] && return 1
        [[ -n "$(echo "$res" | sed -n '/[0-9]\+/p')" && $res -ge 1 && $res -le ${#files[@]} ]] && break
        echo -e "$ESC_UP$ESC_RST" 1>&2
      done
      target="${files[$(($res-1))]}"
    fi
  fi
  echo "$target"
}

fn_publish() {
  target="$1"
  dt="$(fn_read_data "date created" "$target")"
  title="$(fn_read_data "title" "$target")"
  [ -z "$(echo "$dt" | sed -n '/^[0-9]\+$/p')" ] && dt="$(date -d "$dt" "+%s")"
  title="$(echo "$title"| tr " " ".")"
  [ ! -d "$published" ] && mkdir -p "$published"
  cp "$target" "$published/${dt}_${title}" && rm "$target"
  return $?
}

fn_new() {
  f="$(fn_temp_file "$SCRIPTNAME" "$unpublished")" && touch "$f"
  fn_write_data "date created" "$f" "$(date +"%d%b%Y %H:%M:%S")"
  fn_write_data "title" "$f" "$(fn_input_line "title")"
  fn_write_data "content" "$f" "$(fn_input_lines "content")"
  fn_decision "publish?" >/dev/null && fn_publish "$f"
}

fn_mod() {
  declare root
  declare target
  target="$1"
  [[ $? -ne 0 || -z "$target" ]] && return 0
  echo "[info] targeting blog entry '$target'"
  f="$(fn_temp_file "$SCRIPTNAME" "$unpublished")" && touch "$f"
  mv "$target" "$f"
  # edit temp version
  cp "$f" "$f.tmp"

  # edit title
  data="$(fn_read_data "title" "$f.tmp")"
  res=$(fn_decision "edit title$([ -n "$data" ] && echo " [$(fn_sample 50 "$data")]")?" "ynx")
  [ "x$res" = "xx" ] && exit 0
  [ "x$res" = "xy" ] &&\
    fn_write_data "title" "$f.tmp" "$(fn_input_line "title" "$data")"

  # edit content
  data="$(fn_read_data "content" "$f.tmp")"
  res="$(fn_decision "edit content$([ -n "$data" ] && echo -E " [$(fn_sample 50 "$data")]")?" "ynx")"
  [ "x$res" = "xx" ] && exit 0
  [ "x$res" = "xy" ] &&\
    fn_write_data "content" "$f.tmp" "$(fn_input_lines "content" "$data")"

  # modified?
  diff=$(fn_diff "$f.tmp" "$f")
  [ $DEBUG -ge 1 ] && echo "[debug] entry$([ $diff -eq 0 ] && echo " not") modified"
  [ $diff -eq 1 ] && fn_write_data "date modified" "$f.tmp" "$(date +"%d%b%Y %H:%M:%S")"

  # overwrite original with updated
  mv "$f.tmp" "$f"

  # publish
  fn_decision "publish?" >/dev/null && fn_publish "$f"
}

fn_list() {
  declare target
  declare path_
  declare files
  target="$1" && shift
  files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    if [ -d "$target" ]; then
      path_="$target"
    else
      case "$target" in
        "published") path_="$published" ;;
        "unpublished") path_="$unpublished" ;;
        *) echo "[error] invalid target '$target'" && return 1 ;;
      esac
    fi
    IFS=$'\n'; files=($(grep -rl "'title':.*" "$path_")); IFS="$IFSORG"
  fi
  header="id\t${c_red}${c_off}title\tdate created\t${c_bld}${c_off}date modified\tpath"
  tb=""
  l=1
  for f in "${files[@]}"; do
    dt_created="$(sed -n 's/'\''date created'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    dt_modified="$(sed -n 's/'\''date modified'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    title="$(sed -n 's/'\''title'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    tb+="\n[$l]\t$c_red$title$c_off\t$dt_created\t$([ -n "$dt_modified" ] && echo "$c_bld$dt_modified$c_off" || echo "$c_bld$c_off$dt_created")\t$f"
    l=$(($l+1))
  done
  echo "# $target entries"
  echo -e "$header\n${tb:2}" | column -t -s$'\t'
}

option=new
if [ $# -gt 0 ]; then
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [ -n "$(echo "$arg" | sed -n '/^\(h\|help\|new\|publish\|mod\|list\)$/p')" ] && option="$arg" && shift
fi

case "$option" in
  "h"|"help") help && exit ;;
  "new") fn_new ;;
  "publish") fn_publish "$(fn_target "$@")" ;;
  "mod") fn_mod "$(fn_target "$@")" ;;
  "list") fn_list "${1:-"published"}" ;;
  *) echo "[error] unsupported option '$option'" ;;
esac
