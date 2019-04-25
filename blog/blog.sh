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

declare -a column_headers
column_headers=("id" "title" "date created" "date modified" "path")
declare -A column_idxs
column_idxs["id"]=0
column_idxs["title"]=1
column_idxs["date created"]=2
column_idxs["date modified"]=3
column_idxs["path"]=4

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

cmd_restore_cursor='exec 0<&6 1>&7 2>&8; stty echo; echo -en "\'${CUR_VIS}'"; stty -echo'

fn_restore_cursor() {
  eval "$cmd_restore_cursor"
}

fn_cleanup() {
  fn_observer_cleanup
  fn_restore_cursor
}

fn_safe() {
  chr_escape='`'
  s="$1"
  printf "$s" | sed 's/\(['"$chr_escape"']\)/\\\1/g'
}

fn_sample() {
  max="$1" && shift
  data="$@"
  data="$(fn_unquote "$data" | awk 1 ORS='\\n' | awk '{gsub(/\\n$/,""); print}' RS='' ORS='')"
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
  fn_restore_cursor
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
    first="$(fn_escape "awk" "${lines[0]}")"
    last="$(fn_escape "awk" "${lines[$((${#lines[@]}-1))]}")"
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
  grep -rEl "'title':.*$([ -n "$search" ] && echo "$(fn_escape "ere" "$search").*")" "$path_"
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
      while true; do
        res=$(fn_input_line "[user] select target (1-${#files[@]}) or e(x)it")
        [ "x$res" = "xx" ] && return 1
        [[ -n "$(echo "$res" | sed -n '/[0-9]\+/p')" && $res -ge 1 && $res -le ${#files[@]} ]] && break
        echo -en "$CUR_UP$LN_RST" 1>&2
      done
      target="${files[$((res-1))]}"
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
  title="$(fn_path_safe "$(echo "$title" | tr " " ".")")"
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
    fn_write_data "title" "$f.tmp" "$(fn_unquote "$(fn_input_line "title" "$data")")"

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
  declare selected_id
  declare sort
  declare sort_idx
  declare sort_order
  declare path_
  declare files
  target="$1" && shift
  selected_id=$1 && shift
  [ $# -gt 0 ] && sort="$1" && shift
  [ -z "$sort" ] && sort="0|0"
  sort_idx=${sort%|*}
  sort_order=${sort#*|}
  path_="$(fn_target_resolve "$target")"
  files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    [ -z "$path_" ] &&\
      echo "[error] invalid target '$target'" && return 1
    IFS=$'\n'; files=($(fn_target_files "$_path")); IFS="$IFSORG"
  fi
  header=""
  idx=0
  for h in "${column_headers[@]}"; do
    h_mod="$h"
    if [ $idx -eq $sort_idx ]; then
      h_mod="${CLR_HL}$h_mod $([ $sort_order -eq 0 ] && echo "$CHR_ARR_U" || echo "$CHR_ARR_D")${CLR_OFF}"
    elif [ $idx -eq ${column_idxs["title"]} ]; then
      h_mod="${CLR_RED}${CLR_OFF}$h_mod"
    elif [ $idx -eq ${column_idxs["date modified"]} ]; then
      h_mod="${CLR_HL}${CLR_OFF}$h_mod"
    fi
    header+="\t$h_mod"
    idx=$((idx+1))
  done
  header="${header:2}"
  path_escaped="$(fn_escape "sed" "$path_")"

  # raw
  tb=""
  l=1
  for f in "${files[@]}"; do
    title="$(fn_sample 25 "$(fn_safe "$(sed -n 's/^'\''title'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")")")"
    dt_created=$(date -d "$(sed -n 's/'\''date_created'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f")" "+%s")
    dt_modified=$(sed -n 's/'\''date_modified'\'':[ ]*'\''\(.*\)'\''$/\1/p' "$f") && dt_modified=$([ -n "$dt_modified" ] && date -d "$dt_modified" "+%s" || echo $dt_created)
    f2="$f" && [ -n "$(echo "$f2" | sed -n '/^'$path_escaped'/p')" ] && f2=".${f2:${#path_}}"
    tb+="\n$l\t$title\t$dt_created\t$dt_modified\t$f2"
    l=$((l+1))
  done
  declare -a cmd_args_sort
  cmd_args_sort=("-t"$'\t' "-k$((sort_idx+1))")
  [ $sort_order -eq 1 ] && cmd_args_sort[${cmd_args_sort[@]}]="-r"
  sorted="$(echo -e "${tb:2}" | sort "${cmd_args_sort[@]}")"

  # formatted
  tb="$(echo -e "$sorted" | awk -v selected_id=${selected_id-"-1"} -v sort_idx=$((sort_idx+1)) -v column_idx_id=$((column_idxs["id"]+1)) -v column_idx_title=$((column_idxs["title"]+1)) -v column_idx_date_modified=$((column_idxs["date modified"]+1)) '
{
  r=""
  dt=""
  mod=0
  sel=0
  for (idx=1; idx<=NF; idx++) {
    v=$idx
    if ( v ~ /^[0-9]{10}$/ ) {
      v=strftime("%Y%b%d %H:%M:%S",v)
      if (dt == "")
        dt=v
      else if (dt != v)
        mod=1
    }
    if (idx == column_idx_id) {
      if (v == selected_id)
        sel=1
      v="["v"]"
    } else if (idx == column_idx_title) {
      if (sel == 1)
        v="'${CLR_GRN}'"v"'${CLR_OFF}'"
      else
        v="'${CLR_RED}'"v"'${CLR_OFF}'"
    } else if (idx == column_idx_date_modified) {
      if (mod == 1)
        v="'${CLR_HL}'"v"'${CLR_OFF}'"
      else
        v="'${CLR_HL}${CLR_OFF}'"v
    } else if (idx == sort_idx)
      v="'${CLR_HL}${CLR_OFF}'"v
    r=r"\t"v
  }
  gsub(/^\t/,"",r)
  print r
}' FS=$'\t')"
  echo -e "# $target entries\n"
  echo -e "$header\n$(echo -e "$tb")" | column -t -s$'\t'
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

fn_menu_idx_from_id() {
  declare ids
  declare id
  ids="$1" && shift
  id="$1" && shift
  idx=$(echo "$ids" | awk -v rx="^$id\$" 'BEGIN{ idx=1 } { if ($0 ~ rx) print idx; idx=idx+1 }' RS="|")
  echo $idx
}

fn_menu_id_from_idx() {
  declare ids
  declare idx
  ids="$1" && shift
  idx="$1" && shift
  id=$(echo "$ids" | awk -v idx="$idx" 'BEGIN{ l=1 } { if (idx == l) print $0; l=l+1 }' RS="|")
  echo $id
}

fn_menu() {
  [ $# -lt 1 ] && echo "[error] not enough args!" && exit 1

  # setup observer to restore prompt when suspending
  fn_observer "$cmd_restore_cursor"

  stty -echo
  declare target
  declare path_
  declare id
  declare ids
  declare idx
  declare sort_columns
  declare sort_idx
  declare sort_order
  declare res
  declare res2
  target="$1" && shift
  optecho=1
  id=""  # index assigned by order of collection
  ids=""  # current sorted order of said indexes
  idx=""  # current selection position
  sort_order=0
  sort_idx=1
  sort_columns=4
  while true; do
    path_=$(fn_target_resolve "$target")
    [ -z "$path_" ] &&\
      echo "[error] invalid target '$target'" && return 1
    IFS=$'\n'; files=($(fn_target_files "$_path")); IFS="$IFSORG"
    if [ -n "$idx" ]; then
      [ $idx -gt ${#files[@]} ] && idx=${#files[@]}
      [ $idx -eq 0 ] && idx="" && id=""
      [ -n "$idx" ] && id=$(fn_menu_id_from_idx "$ids" "$idx")
    else
      id=""
    fi
    list="$(fn_list "$target" "$id" "$sort_idx|$sort_order" "${files[@]}")"
    ids=$(echo -e "$list" | awk '{ if ( $1 ~ /\[[0-9]+\]/) { gsub(/[\[\]]/,"",$1); print $1 }}' ORS="|")
    [ -n "$id" ] && idx=$(fn_menu_idx_from_id "$ids" "$id")
    echo -e "${TERM_CLR}${list}\n\n"
    no_op=0
    while true; do
      reset=0
      if [ $no_op -eq 0 ]; then
        # reset
        echo -en "$CUR_UP$LN_RST" 1>&2
        echo -en "| (${CLR_HL}t${CLR_OFF})arget:${CLR_GRN}$target${CLR_OFF} (${CLR_HL}i${CLR_OFF})d:$([ -n "$id" ] && echo "${CLR_GRN}$id${CLR_OFF}" || echo "-") (${CLR_HL}${CHR_ARR_U}${CLR_OFF}|${CLR_HL}${CHR_ARR_D}${CLR_OFF}) select | (${CLR_HL}s${CLR_OFF})ort | (${CLR_HL}n${CLR_OFF})ew | (${CLR_HL}e${CLR_OFF})dit | (${CLR_HL}p${CLR_OFF})ublish | (${CLR_HL}d${CLR_OFF})elete | e(${CLR_HL}x${CLR_OFF})it [${CLR_HL}t${CLR_OFF}/${CLR_HL}i${CLR_OFF}/${CLR_HL}${CHR_ARR_U}${CLR_OFF}|${CLR_HL}${CHR_ARR_D}${CLR_OFF}/${CLR_HL}s${CLR_OFF}/${CLR_HL}n${CLR_OFF}/${CLR_HL}e${CLR_OFF}/${CLR_HL}p${CLR_OFF}/${CLR_HL}d${CLR_OFF}/${CLR_HL}x${CLR_OFF}]${CUR_SV}${CUR_INV}"

        res="$(fn_decision "" "t/i/$KEY_ARR_U/$KEY_ARR_D/s/n/e/p/d/x" 0 $optecho)"
      else
        echo -en "${CUR_USV}"
        sleep 0.1
        echo -en "${LN_RTL}"
        res="$(fn_decision "" "t/i/$KEY_ARR_U/$KEY_ARR_D/s/n/e/p/d/x" 0 $optecho)"
      fi
      [ $optecho -eq 0 ] && echo "" 1>&2  # compensate
      case "$res" in
        "x") return 1 ;;
        "t")
          reset=0
          while true; do
            echo -en "$CUR_UP$LN_RST" 1>&2
            stty echo
            res2="$(fn_decision "$(echo -e "| (${CLR_HL}p${CLR_OFF})ublished | (${CLR_HL}u${CLR_OFF})npublished | (${CLR_HL}c${CLR_OFF})ustom | e(${CLR_HL}x${CLR_OFF})it${CUR_INV}")" "pucx")"
            stty -echo
            case "$res2" in
              "x") break ;;
              "p") target="published"; reset=1; break ;;
              "u") target="unpublished"; reset=1; break ;;
              "c")
                echo -en "$CUR_UP$LN_RST" 1>&2
                stty echo
                target_="$(fn_input_line "$(echo -en "| custom path${CUR_VIS}")" "$target")"
                stty -echo
                echo -en "$CUR_INV" 1>&2
                [ "x$target_" = "x$target" ] && break
                path_=$(fn_target_resolve "$target_")
                [ -z "$path_" ] &&\
                  fn_menu_alert "${CLR_RED}[error]${CLR_OFF} invalid target, ignoring!" && continue
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
          while true; do
            echo -en "$CUR_UP$LN_RST" 1>&2
            stty echo
            res2="$(fn_input_line "$(echo -en "| set target id, or e(${CLR_HL}x${CLR_OFF})it${CUR_VIS}")")"
            stty -echo
            echo -en "$CUR_INV" 1>&2
            case "$res2" in
              "x") break ;;
              *)
               [[ -n "$(echo "$res2" | sed -n '/[0-9]\+/p')" && $res2 -ge 1 && $res2 -le ${#files[@]} ]] && idx=$(fn_menu_idx_from_id "$ids" $res2) && reset=1 && break
            esac
          done
          ;;
        "$CHR_ARR_U")
          [[ ${#files[@]} -eq 0 || ( -n "$idx" && $idx -eq 1 ) ]] && no_op=1 && continue
          idx=$([ -n "$idx" ] && echo $((idx-1)) || echo ${#files[@]})
          reset=1
          ;;
        "$CHR_ARR_D")
          [[ ${#files[@]} -eq 0 || ( -n "$idx" && $idx -eq ${#files[@]} ) ]] && no_op=1 && continue
          idx=$([ -n "$idx" ] && echo $((idx+1)) || echo 1)
          reset=1
          ;;
        "s")
          if [ $sort_order -eq 0 ]; then
            sort_order=1
          else
            sort_order=0
            sort_idx=$(echo "($sort_idx + 1) % ${#column_headers[@]}" | bc)
            [ $sort_idx -eq 0 ] && sort_idx=1
          fi
          reset=1
          ;;
        "n")
          fn_new
          idx=""
          reset=1
          ;;
        "e")
          [ -z "$id" ] &&\
            fn_menu_alert "${CLR_RED}[error]${CLR_OFF} invalid target, ignoring!" && continue
          fn_mod ${files[$((id-1))]}
          idx=""
          reset=1
          ;;
        "p")
          [ -z "$id" ] &&\
            fn_menu_alert "${CLR_RED}[error]${CLR_OFF} invalid target, ignoring!" && continue
          fn_publish ${files[$((id-1))]}
          idx=""
          reset=1
          ;;
        "d")
          [ -z "$id" ] &&\
            fn_menu_alert "${CLR_RED}[error]${CLR_OFF} invalid target, ignoring!" && continue
          reset=0
          f="${files[$((id-1))]}"
          title="$(fn_read_data "title" "$f")"
          echo -en "$CUR_UP$LN_RST" 1>&2
          res2="$(fn_decision "| confirm deletion of $title [$f] entry?")"
          [ "x$res2" = "xn" ] && break
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
  . "$f"
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
