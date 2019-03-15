#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
trap fn_cleanup EXIT

RC_DEFAULT="$HOME/.nixTools/$SCRIPTNAME"
declare rc
rc_options="path_blog_root|published|unpublished"
path_blog_root="$HOME/documents/blog"
published="$path_blog_root/published"
unpublished="$path_blog_root/unpublished"
[ -d "$published" ] || mkdir -p "$published" || exit 1
[ -d "$unpublished" ] || mkdir -p "$published" || exit 1

help() {
  echo -e "\nSYNTAX: $SCRIPTNAME [OPTIONS] [MODE [MODE_ARGS]]
\nwhere OPTIONS can be:\n
  -h, --help  : this help information
  -rc FILE, --resource-configuration FILE
    : use settings file FILE (default: ~/nixTools/$SCRIPTNAME
\nand with MODE as:
  new  : creates a new blog entry
  publish  : (re)build and push temp data to 'publshed' target
  mod [SEARCH]  : modify current unpublished item or a published item
                  via title search on SEARCH
  list  : list published entries
  menu  : switch views interactively
"
}

fn_cleanup() {
  echo -en "${CUR_VIS}\n" 1>&2
}

fn_sample() {
  max="$1" && shift
  data="$@"
  data="$(fn_unquote "$data" | awk 1 ORS='\\n' | awk '{gsub(/\\n$/,""); print}' IRS='' ORS='')"
  truncated=0
  len=${#data}
  [ $len -gt $max ] && len=$max && truncated=1
  sample="${data:0:$len}"
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
      fn_edit_line "$data" "$prompt [$(echo -e "${CLR_HL}enter${CLR_OFF}")]: "
      ;;
    "multi_line")
      echo -n "$prompt: " 1>&2
      declare f
      f="$(fn_temp_file $SCRIPTNAME)"
      [ -n "$data" ] &&\
        echo -E -n "$(fn_sample 50 "$data")" 1>&2 &&\
        fn_unquote "$data" > "$f"
      sleep 1
      $EDITOR "$f" 1>/dev/tty
      echo -en "$LN_RST" 1>&2
      data="$(awk 'BEGIN{ printf "'\''" } { print } END{ print "'\''" }' $f)"
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
  [ -z "$(echo "$data" | sed -n '/^'\''/{/'\''$/p;}')" ] &&\
    data="'$data'"
  current="$(fn_read_data "$var" "$target")"
  if [ -z "$current" ]; then
    # add entry
    echo "'$var': ${data[*]}" >> "$target"
  else
    # overwrite entry
    current="'$var': $current"
    IFS=$'\n'; lines=($(echo -e "$current")); IFS="$IFSORG"
    first="$(fn_rx_escape "awk" "${lines[0]}")"
    last="$(fn_rx_escape "awk" "${lines[$((${#lines[@]}-1))]}")"
    update="'$var': $data"
    awk -v update="$update" -v first="$first" -v last="$last" '
BEGIN{ data=""; match1=0; match2=0; rx_first="^"first"$"; rx_last="^"last"$" }
{
  if ($0 ~ rx_first) {
    match1=1; data=data"\n"update;
  } else if (match1 == 1) {
    if (match2 == 1 && /^'\''[a-zA-z0-9_]+'\'': /) {
      match1=0;
      data=data"\n"$0;
    }
  } else
    data=data"\n"$0;

  if ($0 ~ rx_last)
    match2=1;
  else
    match2=0;
}
END{ gsub(/^\n/,"",data); print data }' < "$target" > "$target.tmp"
    check="$(fn_read_data "$var" "$target.tmp")"
    [ "x$check" != "x$data" ] && \
      echo "[error] couldn't validate data write for '$var'" && exit 1
    mv "$target.tmp" "$target"
  fi
}

fn_read_data() {
  var="$1" && shift
  target="$1" && shift
  strip="${1:-0}"
  data=$(awk -v search="$var" '
BEGIN{ data=""; matchx=0; rx="^'\''"search"'\'':" }
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
END{ gsub(/^[ ]*/,"",data); gsub(/[ ]*$/,"",data); print data }' < "$target")
  [ $strip -eq 1 ] && fn_unquote "$data" || echo -n "$data"
}

fn_unquote() {
  echo -n "$1" | sed '1s/^'\''//;$s/'\''$//'
}

fn_target_files() {
  declare target
  declare search
  target="$1" && shift
  search="${1:-""}"
  grep -rl "'title':.*$([ -n "$search" ] && echo "$(fn_rx_escape "grep" "$search").*")" "$path_"
}

fn_target_resolve() {
  declare target
  declare path_
  target="$1"
  case "$target" in
    "published") path_="$published" ;;
    "unpublished") path_="$unpublished" ;;
    *) [ -d "$target" ] && path_="$target" ;;
  esac
  echo "$path_"
  [ -z "$path_" ] && return 1
}

fn_target_select() {
  declare target
  [ $# -gt 0 ] && target="$1" && shift
  if [ -f "$target" ]; then
    [ -z "$(grep "'title':.*" "$target")" ] &&\
      echo "[error] invalid target file '$target'" 1>&2 && return 1
  else
    declare path_
    declare search
    declare files
    path_="$(fn_target_resolve "$target")"
    [[ -z "$path_" && $# -eq 0 ]] &&\
      path_="$path_blog_root" && search="$target"
    [ -z "$path_" ] &&\
      echo "[error] invalid target '$target'" && return 1
    [ $# -gt 0 ] && search="$1" && shift
    IFS=$'\n'; files=($(fn_target_files "$_path" "$search")); IFS="$IFSORG"
    if [ ${#files[@]} -eq 0 ]; then
      echo "[info] no blog entr$([ -n "$search" ] && echo "y found using search term '$search'" || echo "ies found")" 1>&2 && return 1
    elif [ ${#files[@]} -eq 1 ]; then
      target="${files[0]}"
    elif [ ${#files[@]} -gt 1 ]; then
      fn_list "$target" "" "${files[@]}" 1>&2
      declare res
      while [ 1 ]; do
        res=$(fn_input_line "[user] select target (1-${#files[@]}) or e(x)it")
        [ "x$res" = "xx" ] && return 1
        [[ -n "$(echo "$res" | sed -n '/[0-9]\+/p')" && $res -ge 1 && $res -le ${#files[@]} ]] && break
        echo -en "$CUR_UP$LN_RST" 1>&2
      done
      target="${files[$(($res-1))]}"
    fi
  fi
  echo "$target"
}

fn_publish() {
  declare target
  target="$1"
  dt="$(fn_read_data "date_created" "$target" 1)"
  title="$(fn_read_data "title" "$target" 1)"
  [ -z "$(echo "$dt" | sed -n '/^[0-9]\+$/p')" ] && dt="$(date -d "$dt" "+%s")"
  title="$(echo "$title"| tr " " ".")"
  [ ! -d "$published" ] && mkdir -p "$published"
  cp "$target" "$published/${dt}_${title}" && rm "$target"
  return $?
}

fn_new() {
  f="$(fn_temp_file "$SCRIPTNAME" "$unpublished")" && touch "$f"
  fn_write_data "date_created" "$f" "$(date +"%d%b%Y %H:%M:%S")"
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
  [ $diff -eq 1 ] && fn_write_data "date_modified" "$f.tmp" "$(date +"%d%b%Y %H:%M:%S")"

  # overwrite original with updated
  mv "$f.tmp" "$f"

  # publish
  fn_decision "publish?" >/dev/null && fn_publish "$f"
}

fn_list() {
  declare target
  declare selected
  declare path_
  declare files
  target="$1" && shift
  selected=$1 && shift
  path_="$(fn_target_resolve "$target")"
  files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    [ -z "$path_" ] &&\
      echo "[error] invalid target '$target'" && return 1
    IFS=$'\n'; files=($(fn_target_files "$_path")); IFS="$IFSORG"
  fi
  header="id\t${CLR_RED}${CLR_OFF}title\tdate created\t${CLR_HL}${CLR_OFF}date modified\tpath"
  tb=""
  l=1
  path_escaped="$(fn_rx_escape "sed" "$path_")"
  for f in "${files[@]}"; do
    c_title="$CLR_RED"
    [[ -n "$selected" && $l -eq $selected ]] && c_title="$CLR_GRN"
    dt_created="$(sed -n 's/'\''date_created'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    dt_modified="$(sed -n 's/'\''date_modified'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    title="$(sed -n 's/'\''title'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")"
    f2="$f"
    [ -n "$(echo "$f2" | sed -n '/^'$path_escaped'/p')" ] &&\
      f2=".${f2:${#path_}}"
    tb+="\n[$l]\t$c_title$title$CLR_OFF\t$dt_created\t$([ -n "$dt_modified" ] && echo "$CLR_HL$dt_modified$CLR_OFF" || echo "$CLR_HL$CLR_OFF$dt_created")\t$f2"
    l=$(($l+1))
  done
  echo -e "# $target entries\n"
  echo -e "$header\n${tb:2}" | column -t -s$'\t'
}

fn_menu_alert() {
  declare alert
  declare duration
  alert="$1" && shift
  duration=${1:-2}
  echo -en "$CUR_UP$LN_RST" 1>&2
  echo -e "$alert"
  echo -e -n "$CUR_INV" 1>&2
  sleep $duration
  echo -e -n "$CUR_VIS" 1>&2
}

fn_menu() {
  [ $# -lt 1 ] && echo "[error] not enough args!" && exit 1
  declare target
  declare path_
  declare id
  declare res
  declare res2
  target="$1" && shift
  id=""
  while [ 1 ]; do
    path_=$(fn_target_resolve "$target")
    [ -z "$path_" ] &&\
      echo "[error] invalid target '$target'" && return 1
    IFS=$'\n'; files=($(fn_target_files "$_path")); IFS="$IFSORG"
    [[ -n "$id" && $id -gt ${#files[@]} ]] &&\
      id=${#files[@]}
    list="$(fn_list "$target" "$id" "${files[@]}")"
    echo -e "${TERM_CLR}${list}\n\n"
    no_op=0
    while [ 1 ]; do
      if [ $no_op -eq 0 ]; then
        # reset
        echo -en "$CUR_UP$LN_RST" 1>&2
        res="$(fn_decision "$(echo -e "| (${CLR_HL}t${CLR_OFF})arget:${CLR_GRN}$target${CLR_OFF} (${CLR_HL}i${CLR_OFF})d:$([ -n "$id" ] && echo "${CLR_GRN}$id${CLR_OFF}" || echo "-") (${CLR_HL}${CHR_ARR_U}${CLR_OFF}|${CLR_HL}${CHR_ARR_D}${CLR_OFF}) select | (${CLR_HL}p${CLR_OFF})ublish | (${CLR_HL}e${CLR_OFF})dit | (${CLR_HL}d${CLR_OFF})elete | e(${CLR_HL}x${CLR_OFF})it${CUR_INV}")" "t/i/$KEY_ARR_U/$KEY_ARR_D/e/p/d/x" 1 0)"
      else
        res="$(fn_decision "" "t/i/$KEY_ARR_U/$KEY_ARR_D/e/p/d/x" 1 0)"
      fi
      case "$res" in
        "x") return 1 ;;
        "t")
          reset=0
          while [ 1 ]; do
            echo -en "$CUR_UP$LN_RST" 1>&2
            res2="$(fn_decision "$(echo -e "| (${CLR_HL}p${CLR_OFF})ublished | (${CLR_HL}u${CLR_OFF})npublished | (${CLR_HL}c${CLR_OFF})ustom | e(${CLR_HL}x${CLR_OFF})it${CUR_INV}")" "pucx")"
            case "$res2" in
              "x") break ;;
              "p") target="published"; reset=1; break ;;
              "u") target="unpublished"; reset=1; break ;;
              "c")
                echo -en "$CUR_UP$LN_RST" 1>&2
                target_="$(fn_input_line "$(echo -en "| custom path${CUR_VIS}")" "$target")"
                [ "x$target_" = "x$target" ] && break
                path_=$(fn_target_resolve "$target_")
                [ -z "$path_" ] &&\
                  fn_menu_alert "$CLR_RED[error]$CLR_OFF invalid target, ignoring!" && continue
                target="$target_"
                id=""
                reset=1;
                break;
                ;;
            esac
          done
          ;;
        "i")
          reset=0
          while [ 1 ]; do
            echo -en "$CUR_UP$LN_RST" 1>&2
            res2="$(fn_input_line "$(echo -en "| set target id, or e(${CLR_HL}x${CLR_OFF})it${CUR_VIS}")")"
            case "$res2" in
              "x") break ;;
              *)
               [[ -n "$(echo "$res2" | sed -n '/[0-9]\+/p')" && $res2 -ge 1 && $res2 -le ${#files[@]} ]] && id=$res2 && reset=1 && break
            esac
          done
          ;;
        "$CHR_ARR_U")
          [[ -n "$id" && $id -eq 1 ]] && no_op=1 && continue
          id=$([ -n "$id" ] && echo $(($id-1)) || echo ${#files[@]})
          reset=1
          ;;
        "$CHR_ARR_D")
          [[ -n $id && $id -eq ${#files[@]} ]] && no_op=1 && continue
          id=$([ -n $id ] && echo $(($id+1)) || echo 1)
          reset=1
          ;;
        "e")
          [ -z "$id" ] &&\
            fn_menu_alert "$CLR_RED[error]$CLR_OFF invalid target, ignoring!" && continue
          fn_mod ${files[$(($id-1))]}
          id=""
          ;;
        "p")
          [ -z "$id" ] &&\
            fn_menu_alert "$CLR_RED[error]$CLR_OFF invalid target, ignoring!" && continue
          fn_publish ${files[$(($id-1))]}
          id=""
          ;;
        "d")
          [ -z "$id" ] &&\
            fn_menu_alert "$CLR_RED[error]$CLR_OFF invalid target, ignoring!" && continue
          reset=0
          f="${files[$(($id-1))]}"
          title="$(fn_read_data "title" "$f")"
          echo -en "$CUR_UP$LN_RST" 1>&2
          res2="$(fn_decision "| confirm deletion of $title [$f] entry?")"
          [ "x$res2" == "xn" ] && break
          if [ ! -e "$f" ]; then
            fn_menu_alert "[error] target file '$f' doesn't exist!"
          else
            rm -f "$f"
            fn_menu_alert "[info] target file '$f' deleted"
          fi
          reset=1
          ;;
      esac
      [ $reset -eq 1 ] && break
    done
  done
  fn_cleanup
}

fn_test() {
  [ $# -lt 1 ] && echo "[error] not enough args!" && exit 1
  declare target
  target="$1" && shift
  if [ $# -eq 0 ]; then
    declare d
    declare f
    title="test"
    content="content\ncontent2"
    dt="$(date)"
    d="$(fn_temp_dir $SCRIPTNAME)"
    f="$(fn_temp_file $SCRIPTNAME "$d")"
    echo -e "'title': '$title'\n'content': '$content'\n'date_modified': '$dt'" > $f
    echo "## test file: $f" ##
    cat "$f"
    echo "####"
    case "$target" in
      "fn_read_data")
        tests=("title title"
               "content content")
        for s in "${tests[@]}"; do
          in="$(echo "$s" | cut -d' ' -f1)"
          out="$(eval "echo -e $""$(echo "$s" | cut -d' ' -f2)")"
          res=$($target "$in" "$f")
          echo "[$target | $in] out: '$res' | $([ "x$res" = "x$out" ] && echo "pass" || echo "fail")"
        done
        ;;
      *)
        $target "$@"
    esac
    rm -rf "$d"
  else
    $target "$@"
  fi
}

# options parse
declare -a args
while [ -n "$1" ]; do
  arg="$(echo "$1" | awk '{gsub(/^[ ]*-*/,"",$0); print(tolower($0))}')"
  [[ -z $option && -n "$(echo "$arg" | sed -n '/^\(h\|help\|new\|publish\|mod\|list\|menu\|test\)$/p')" ]] && option="$arg" && shift && continue
  case "$arg" in
    "rc"|"resource-configuration") shift && rc="$1" ;;
    *) args[${#args[@]}]="$1"
  esac
  shift
done
option=${option:-new}

# options validation
[[ -n "$rc" && ! -f "$RC" ]] && echo "[error] invalid rc file '$rc'" && exit 1
rc="${rc:-$RC_DEFAULT}"

if [ -f "$rc" ]; then
  # override defaults
  f="$(fn_temp_file "$SCRIPTNAME")"
  sed -n '/\('"($(echo "$rc_options" | sed 's/|/\\|/g')"'\)/p' "$rc" > "$f"
  if [ $DEBUG -ge 1 ]; then
    echo "# rc options: $f"
    cat "$f"
  fi
  source "$f"
  rm "$f"
fi

case "$option" in
  "h"|"help") help && exit ;;
  "new") fn_new ;;
  "publish") fn_publish "$(fn_target_select "${args[@]}")" ;;
  "mod") fn_mod "$(fn_target_select "${args[@]}")" ;;
  "list") fn_list "${args[0]:-"published"}" ;;
  "menu") fn_menu "${args[0]:-"published"}" ;;
  "test") fn_test "${args[@]}" ;;
  *) echo "[error] unsupported option '$option'" ;;
esac
