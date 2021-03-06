#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME=${0##*/}
IFSORG="$IFS"
DEBUG=${DEBUG:-0}

diff_bin="$(which diff)"
git_bin="$(which git)"
diffs=0
TARGET_DIFFS_DEFAULT="increments"
declare target_diffs
TARGET_MATCHES_DEFAULT="matches"
declare target_matches
remove_dupes=0
remove_zeros=0
declare blacklist
declare group_by_basename; group_by_basename=0
interactive_cleaning=1
declare -a targets
target=${INCREMENTS_TARGET:-}
search=(${INCREMENTS_SEARCH:-})
variants=${INCREMENTS_VARIANTS:-}
declare -a transforms
precedence=${INCREMENTS_PRECEDENCE:-}
declare tmp
diff_format_git=0
diff_format_paths=0
GIT_DIFF_HEADER=\
"From fedcba10987654321012345678910abcdef Mon Sep 17 00:00:00 2001\n"\
"From: @NAME <@EMAIL>\nDate: @DATE\nSubject: @SUBJECT\n\n---\n"
GIT_DIFF_FOOTER="--\n@VERSION"
GIT_DIFF_DT_FORMAT="%a, %d %b %Y %T %z"  # e.g. Mon, 1 Jan 1970 00:00:00 +0000
diff_numeric_prefixes=0
GIT_DIFF_SUBJECT=${GIT_DIFF_SUBJECT:-"[diff]"}
DIFF_TARGET_BASE_PATH=${DIFF_TARGET_BASE_PATH:-""}
DIFF_TARGET_FILE=${DIFF_TARGET_FILE:-""}
# backing table fields
column_idx_date=1
column_idx_size=2
column_idx_file=3
column_idx_group=4
column_idx_last=$column_idx_group
declare column_idx_dupe
declare column_idx_precedence

help() {
  echo -e "
SYNTAX: $SCRIPTNAME [OPTIONS] search [search2 ..]
\nwhere OPTIONS can be:
  -t TARGETS, --target TARGETS  : pipe ('|') delimited list of search
                                  targets (paths / tar archives)
  -v VARIANTS, --variants VARIANTS  : consider search variants given
                                      by application of (sed) regexp
                                      transformations in VARIANTS file
  -pp PATHS, --path-precedence PATHS : pipe ('|') delimited list of
                                       partial paths for matching on
                                       search results in order to
                                       override the default order of
                                       the ultimate set when desired
  -nd, --no-duplicates  : use only first instance of any duplicate
                          files matched
  -nz, --no-zeros  : ignore 0 length files
  -bl LIST, --blacklist LIST  : pipe ('|') delimited list of strings
                                to rx match against search results
                                with any matched files removed from
                                the ultimate set
  -g, --group  : group matched files by basename for diffs
  -d, --diffs  : output incremental diffs of search matches
  -dd, --dump-diffs PATH  : write diffs to PATH (default: increments)
  -dm, --dump-matches PATH  : copy search matches to PATH
                              (default: matches)
  -ac, --auto-clean  : automatically clean dump targets (no prompt!)
  -dfp, --diff-format-paths  : format paths in any incremental diffs
                               generated to the standard
                               'a[/PATH]/FILE' 'b[/PATH]/FILE pair.
                               by default, PATH is stripped, and FILE
                               is set to the latter of the diff pair's
                               names. see environment variable below
                               for overrides
  -dfg, --diff-format-git  : add git mailinfo compatible headers to
                             diff files
  -dnp, --diff-numeric-prefixes  : prefix diff number to file name
\nenvironment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
  DIFF_TARGET_BASE_PATH  : base path of file to be use in any
                           incremental diffs generated e.g.
                           'a/DIFF_TARGET_BASE_PATH/FILE'
  DIFF_TARGET_FILE  : file name override for any incremental diffs
                      generated. e.g. 'b/DIFF_TARGET_FILE'
  GIT_DIFF_SUBJECT  : subject line for any incremental diffs generated
"
}

fn_clean_up() {
  [ -n "$tmp" ] && [ -e "$tmp" ] && rm -rf "$tmp" 2>/dev/null 1>&2
}

fn_clean() {
  declare target
  declare interactive
  declare files

  target="$1" && shift
  [ ! -e "$target" ] && echo "[error] invalid target '$target'" && return 1
  interactive=${1:-1}

  IFS=$'\n'; files=($(find "$target" -mindepth 1 -type "f")); IFS="$IFSORG"
  if [ ${#files[@]} -gt 0 ]; then
    res="y"
    if [ $interactive -eq 1 ]; then
      echo -n "[user] target '$target' cleanup, purge ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")?"
      res=$(fn_decision)
    else
      echo "[info] target '$target' cleanup, purging ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")"
    fi
    [ "x$res" = "xy" ] && rm -r "$target/"*
  fi
}

fn_precedence() {
  declare s_table
  declare pss
  s_table="$1" && shift
  pss="$1" && shift

  IFS=$'|'; precedence_sets_searches=($(echo "$precedence")); IFS="$IFSORG"
  l=0
  for pss in "${precedence_sets_searches[@]}"; do
    s_table="$(echo -e "$s_table" | sed '/^\([^\t]\+\t\)\{'$((column_idx_precedence-1))'\}[0-9]\+/{b;};s/^\(\([^\t]\+\t\)\{'$((column_idx_file-1))'\}[^\t]*'"$(fn_escape "sed" "$pss")"'[^\t]*\(\(\t[^\t]\+\)\+$\|$\)\)/\1\t'$l'/')"
    l=$((l+1))
  done
  echo "$s_table"
}

fn_process() {

  if [ -n "$variants" ]; then
    if [ ! -f "$variants" ]; then
      echo "[error] invalid variants file set '$variants'. ignoring!"
    else
      declare -a search2
      search2=""
      IFS=$'\n'; transforms=($(cat "$variants")); IFS="$IFSORG"
      for s in "${search[@]}"; do
        search2+="$s\n"
        for transform in "${transforms[@]}"; do
          v=$(echo "$s" | sed -n 's'"$transform"'p')
          [ -n "${v}" ] && search2+="$v\n"
        done
      done
      # unique only
      IFS=$'\n'; search=($(echo -e "$search2" | sort -u)); IFS="$IFSORG"
    fi
  fi

  # search
  declare files
  declare matches
  declare -a cmdargs_find
  cmdargs_find=("-mindepth" 1 "-type" "f")
  [ $remove_zeros -eq 1 ] && cmdargs_find=("${cmdargs_find[@]}" "-size" "+0b")
  for target in "${targets[@]}"; do
    if [ ! -d "$target" ]; then
      # archive extraction
      globs=(); for s in "${search[@]}"; do globs=("${globs[@]}" "--wildcards" "*$(echo "$s" | sed 's/^\(\.\*\)*//;s/\(\.\*\)*$//;s/\.\*/*/g')*"); done
      tmp=$(fn_temp_dir "$SCRIPTNAME")
      tar -C "$tmp" -x "${globs[@]}" -f "$target" 2>/dev/null
      res=$?
      if [ $res -ne 0 ]; then
        [ $res -eq 2 ] && \
          echo "[info] ignoring GNU tar 'not found in archive' 'errors'" 1>&2 || return $res
      fi
      target=$tmp
    fi
    # directory search
    rx=""; for s in "${search[@]}"; do rx+="\|$s"; done; rx="^.*/?\(${rx:2}\)$"
    files="$(find "$target" "${cmdargs_find[@]}" -iregex "$rx")"
    matches+="\n$files"
    count=$(echo -e "$files" | wc -l)
    [ $DEBUG -ge 1 ] && echo "[debug] searched target '$target' for '${search[*]}, matched $count file$([ $count -ne 1 ] && echo "s")'" 1>&2
  done
  matches="${matches:2}"
  IFS=$'\n'; files=($(echo -e "$matches")); IFS="$IFSORG"
  [ ${#files[@]} -eq 0 ] && echo "[info] no files found" && return 1
  echo "[info] matched ${#files[@]} file$([ ${#files[@]} -ne 1 ] && echo "s")" 1>&2

  # blacklist
  if [ -n "$blacklist" ]; then
    blacklist="$(fn_escape "sed" "$(echo "$blacklist" | sed 's/|/\\|/g')")"
    declare -a files2
    i=0
    for f in "${files[@]}"; do
      [ -z "$(echo "$f" | sed -n '/\('"$blacklist"'\)/p')" ] &&\
         files2[$i]="$f" && i=$((i+1))
    done

    filtered=$((${#files[@]}-${#files2[@]}))
    if [ $filtered -gt 0 ]; then
      echo "[info] blacklist filtered $filtered file$([ $filtered -ne 1 ] && echo "s")"
      files=("${files2[@]}")
    fi
  fi

  # dump matches
  if [ -n "$target_matches" ]; then
    [ ! -d "$target_matches" ] && mkdir -p "$target_matches"
    fn_clean "$target_matches" $interactive_cleaning
    for f in "${files[@]}"; do cp -a --parents "$f" "$target_matches/"; done
    echo "[info] dumped ${#files[*]} matches to '$target_matches'" 1>&2
  fi

  maxlen_path=4
  maxlen_size=4
  s=""
  for f in "${files[@]}"; do
    [ ${#f} -gt $maxlen_path ] && maxlen_path=${#f}
    i=`stat -L "$f"`
    ts=`echo -e "$i" | grep "Modify" | cut -d' ' -f2- | xargs -I '{}' date -d '{}' '+%s'`
    sz=`echo -e "$i" | sed -n 's/.*Size: \([0-9]\+\).*/\1/p'`
    [ ${#sz} -gt $maxlen_size ] && maxlen_size=${#sz}
    s="$s\n$ts\t$sz\t$f"
  done
  s="${s:2}"
  sorted="$(echo -e "$s" | sort -n -t$'\t' -k$column_idx_date)"
  [ $DEBUG -ge 2 ] && echo "[debug] timestamp sorted table" 1>&2 && echo -e "$sorted" | column -t -s $'\t' 1>&2 && echo 1>&2

  # grouping
  IFS=$'\n'; sorted=($(echo -e "$sorted")); IFS="$IFSORG"
  declare -a groups
  if [ $group_by_basename -eq 1 ]; then
    # basename / variant based grouping
    declare -a names
    l=0
    for r in "${sorted[@]}"; do
      names[$l]="$(basename "$(echo "${sorted[$l]}" | cut -d$'\t' -f$column_idx_file)")"
      l=$((l+1))
    done
    match_types=("" "base" "variant" "reverse variant")
    l=0
    l2=0
    group=0
    declare -a matches
    for l in $(seq $l 1 $((${#names[@]}-1))); do
      # construct match idx|type pairs
      matches=()
      matches_=$l
      n="${names[$l]}"
      g=${groups[$l]}
      for l2 in $(seq $((l+1)) 1 $((${#names[@]}-1))); do
        n2="${names[$l2]}"
        g2=${groups[$l2]}
        if [[ -n "$g" && -n "$g2" ]]; then
          matches_=$((matches_+1))
        else
          # test for variant basename match
          match=0
          if [ "$n2" = "$n" ]; then
            match=1
          elif [ ${#transforms[@]} -gt 0 ]; then
            for transform in "${transforms[@]}"; do
              t=$(echo "$n2" | sed 's'"$transform")
              [ -z "$t" ] && continue
              v=$(echo "$n" | sed -n '/'"$(fn_escape "sed" "$t")"'/p')
              if [ -n "$v" ]; then
                match=2
              else
                # reverse variant
                t=$(echo "$n" | sed 's'"$transform")
                [ -z "$t" ] && continue
                v=$(echo "$n2" | sed -n '/'"$(fn_escape "sed" "$t")"'/p')
                [ -n "$v" ] && match=3
              fi
            done
          fi
          if [ $match -gt 0 ]; then
            matches_=$((matches_+1))
            if [ -z "$g" ]; then
              # matched to (outer) existing group
              matches[${#matches[@]}]="$l|0"
              [ -n "$g2" ] && g=$g2
            fi
            [ -z "$g2" ] && matches[${#matches[@]}]="$l2|$match"
          fi
        fi
      done
      # allocate gid
      [ $DEBUG -ge 4 ] &&\
        echo "[debug] names: ${#names[@]}, iteration $l, matches: ${#matches[@]}\n${matches[@]}"
      new=0
      [ -z "$g" ] && group=$((group+1)) && new=1
      for match in "${matches[@]}"; do
        idx="${match%|*}"
        type="${match#*|}"
        [ $DEBUG -ge 2 ] &&\
          echo -e "[debug] $([ $type -gt 0 ] && echo "${match_types[$type]} match, ")allocating to $([ $new -eq 1 ] && echo "new" || echo "existing") group id ${g:-$group}\n [$([ -n "${groups[$l]}" ] && echo ${groups[$l]} || printf "-")] $n$([ $idx -ne $l ] && echo -e "\n [$([ -n "${groups[$idx]}" ] && echo "${groups[$idx]}" || printf "-")] ${names[$idx]}")"
        [ -z ${groups[$l]} ] && groups[$l]=${g:-$group}
        [ -z ${groups[$idx]} ] && groups[$idx]=${g:-$group}
      done
      groups[$l]=${g:-$group}
      [ $matches_ -eq ${#names[@]} ] && break
    done
  else
    groups=($(printf "%.s 1" $(seq 1 1 ${#sorted[@]})))
  fi
  grouped=""
  l=0
  for r in "${sorted[@]}"; do
    grouped+="\n$r\t${groups[$l]}"
    l=$((l+1))
  done
  sorted="${grouped:2}"
  sorted="$(echo -e "${grouped:2}" | sort -n -t$'\t' -k$column_idx_group -k$column_idx_date)"
  [ $DEBUG -ge 2 ] && echo "[debug] group > timestamp sorted table" 1>&2 && echo -e "$sorted" | column -t -s $'\t' 1>&2 && echo "" 1>&2

  # duplicates
  if [ $remove_dupes -eq 1 ]; then
    column_idx_dupe=$((column_idx_last+1))
    column_idx_last=$column_idx_dupe

    IFS=$'\n'; sorted_size=($(echo -e "$sorted" | sort -n -t $'\t' -n -r -k$column_idx_size)); IFS="$IFSORG" # sort by size
    l1=0
    compared_dupe=""
    while [ $l1 -lt ${#sorted_size[@]} ]; do
      sz="$(echo "${sorted_size[$l1]}" | cut -d$'\t' -f$column_idx_size)"
      f="$(echo "${sorted_size[$l1]}" | cut -d$'\t' -f$column_idx_file)"
      compared_dupe+="\n${sorted_size[$l1]}\t0"  # unique or first
      l1=$((l1+1))
      l2=0
      s=()
      while [[ $((l1+l2)) -lt ${#sorted_size[@]} && \
               $sz -eq $(echo "${sorted_size[$((l1+l2))]}" | cut -d$'\t' -f$column_idx_size) ]]; do
        # collect any files with same size as first/base, yet to be deemed 'dupe'
        f2="$(echo "${sorted_size[$((l1+l2))]}" | cut -d$'\t' -f$column_idx_file)"
        dupe="$(echo "${sorted_size[$((l1+l2))]}" | cut -d$'\t' -f$column_idx_dupe)"
        [ -z "$dupe" ] && s[${#s[@]}]="$f2"
        l2=$((l2+1))
      done
      if [ ${#s[@]} -gt 0 ]; then
        # make comparison
        compared="$(fn_files_compare "$f" "${s[@]}")"
        res=$?
        [ $res -ne 0 ] && return $res
        # create merged data subset for sort
        IFS=$'\n'; compared=($(echo -e "$compared")); IFS="$IFSORG"
        s=""
        for l3 in $(seq 0 1 $((l2-1))); do
          s2="${sorted_size[$((l1+l3))]}"
          c="${compared[$l3]}"
          s+="\n$([ ${c#*$'\t'} -eq 1 ] && echo "${s2%$'\t'*%}\t1" || echo "${sorted_size[$((l1+l3))]}")"
        done
        # update set / replace subset with any dupes first
        IFS=$'\n'; compared=($(echo -e "$s" | sort -n -t$'\t' -k$column_idx_dupe -r)); IFS="$IFSORG"
        dupes_count=0
        for l3 in $(seq 0 1 $((l2-1))); do
          sorted_size[$((l1+l3))]="${compared[$l3]}"
          if [ -n "$(echo "${compared[$l3]}" | cut -d$'\t' -f$column_idx_dupe)" ]; then
            compared_dupe+="\n${compared[$l3]}"  # dupe
            dupes_count=$((dupes_count+1))
          fi
        done
        # move index beyond dupes for next base
        l1=$((l1+dupes_count))
      fi
    done
    compared_dupe="${compared_dupe:2}"
    [ $DEBUG -ge 2 ] && echo "[debug] duplicate tested table" 1>&2 && echo -e "$compared_dupe" | column -t -s $'\t' 1>&2 && echo "" 1>&2
    sorted="$(echo -e "$compared_dupe" | sort -n -t$'\t' -k$column_idx_date | sed '/\t1$/d;')"
    [ $DEBUG -ge 2 ] && echo "[debug] timestamp sorted duplicate free table" 1>&2 && echo -e "$sorted" | column -t -s $'\t' 1>&2 && echo "" 1>&2
  fi

  matches=$(echo -e "$sorted" | wc -l)
  [ ${#files[@]} -ne ${#sorted[@]} ] && echo "[info] ${matches} unique file$([ $matches -ne 1 ] && echo "s")" 1>&2

  # precedence
  if [ -n "$precedence" ]; then
    column_idx_precedence=$((column_idx_last+1))
    column_idx_last=$column_idx_precedence
    s="$(echo -e "$sorted" | sort -n -t$'\t' -k$column_idx_group)"
    IFS=$'\n'; rs=($(echo -e "$s")); IFS="$IFSORG"
    s_=""
    ss=""
    g_last=""
    l=1
    for r in "${rs[@]}"; do
      IFS=$'\t'; fields=($(echo -e "$r")); IFS="$IFSORG"
      g=${fields[$((column_idx_group-1))]}
      [ -z "$g_last" ] && g_last="$g"
      if [[ $l -eq ${#rs[@]} || "$g" != "$g_last" ]]; then
        # process group
        [ $l -eq ${#rs[@]} ] && ss+="\n$r"
        s_+="\n$(fn_precedence "${ss:2}" "$precedence")"
        [ $l -ne ${#rs[@]} ] && ss="\n$r"
      else
        ss+="\n$r"
      fi
      l=$((l+1))
    done
    s="$(echo -e "${s_:2}" | sed '/^\([^\t]\+\t\)\{'$((column_idx_precedence-1))'\}[0-9]\+/{b;};s/^\(.*\)$/\1\t'$l'/')"
    sorted="$(echo "$s" | sort -n -t$'\t' -k$column_idx_group -k$column_idx_precedence -k$column_idx_date)"
    [ $DEBUG -ge 2 ] && echo "[debug] group > precedence > timestamp sorted table" 1>&2 && echo -e "$sorted" | column -t -s $'\t' 1>&2 && echo "" 1>&2
  fi

  # switch to array items
  IFS=$'\n'; sorted=($(echo -e "$sorted")); IFS="$IFSORG"

  # diffs
  declare -a last
  last[0]="-"
  for l in $(seq 1 1 ${#groups[@]}); do
    last[$l]="/dev/null"
  done
  if [[ $diffs -eq 1 || -n "$target_diffs" ]]; then
    if [ -z "$diff_bin" ]; then
      echo "[error] no 'diff' binary found in your PATH" 1>&2
    else
      if [ -n "$target_diffs" ]; then
        [ ! -d "$target_diffs" ] && mkdir -p "$target_diffs"
        fn_clean "$target_diffs" $interactive_cleaning
      fi
      name=""
      email=""
      if [ -n "$git_bin" ]; then
        name="$($git_bin config --get user.name)"
        email="$($git_bin config --get user.email)"
      fi
      l=1
      for r in "${sorted[@]}"; do
        [ $DEBUG -ge 3 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
        IFS=$'\t'; fields=($(echo -e "$r")); IFS="$IFSORG"
        ts=${fields[$((column_idx_date-1))]}
        sz=${fields[$((column_idx_size-1))]}
        f=${fields[$((column_idx_file-1))]}
        g=${fields[$((column_idx_group-1))]}
        last="${last[$g]}"
        diff_bin_args=("-u" "$last" "$f")
        last[$g]="$f"
        diff_pathfile="$target_diffs/$ts.diff"
        [ $diff_numeric_prefixes -eq 1 ] &&\
          diff_pathfile="$(printf "%s/%04d_%s" "$target_diffs" $l "$ts.diff")"
        [ $DEBUG -ge 2 ] && echo -e "[debug] diff:\n $CHR_ARR_D | $last\n $CHR_ARR_U | $f"
        # binary file check
        diff_check="$($diff_bin "${diff_bin_args[@]}" | head -n1)"
        if [ -n "$(echo "$diff_check" | sed -n '/^Binary files.*differ$/p')" ]; then
          [ -z "$git_bin" ] &&\
            echo "[info] binary diff for file '$f' not supported, skipping" && continue
          d_tmp="$(fn_temp_dir $SCRIPTNAME)"
          cp -a --parent "$f" "$d_tmp" || exit 1
          cd "$d_tmp" >/dev/null 2>&1 || exit 1
          $git_bin init > /dev/null 2>&1 || exit 1
          $git_bin add . > /dev/null 2>&1 || exit 1
          $git_bin commit -m "binary patch" >/dev/null 2>&1 || exit 1
          $git_bin format-patch -1 HEAD > /dev/null 2>&1 || exit 1
          cd - >/dev/null 2>&1 || exit 1
          [ $diffs -eq 1 ] && sed '/^---$/,/^--\ \?$/p' $d_tmp/00* | sed -n '1,/^diff/{/^diff/b;d};$d'
          [ -n "$target_diffs" ] &&\
            sed -n '/^---$/,/^--\ \?$/p' $d_tmp/00* | sed '1,/^diff/{/^diff/b;d};$d' > "$diff_pathfile"
          rm -rd "$d_tmp"
        else
          if [[ $diffs -eq 1 && -n "$target_diffs" ]]; then
            $diff_bin "${diff_bin_args[@]}" | tee "$diff_pathfile"
          elif [ $diffs -eq 1 ]; then
            $diff_in "${diff_bin_args[@]}"
          else
            $diff_bin "${diff_bin_args[@]}" > "$diff_pathfile"
          fi
        fi

        if [[ $diff_format_git -eq 1 && -e $diff_pathfile && -e "$diff_pathfile" ]]; then
          # add header / footer
          diff_header="$GIT_DIFF_HEADER"
          diff_footer="$GIT_DIFF_FOOTER"
          [ -n "$git_bin" ] &&\
            diff_footer="$(echo "$GIT_DIFF_FOOTER" | sed 's/@VERSION/'"$($git_bin --version | sed -n 's/.* \([0-9.]*\).*/\1/p#')"'/')"
          diff_header="$(echo "$diff_header" | sed 's/@DATE/'"$(date -d "@$ts" "+$GIT_DIFF_DT_FORMAT")"'/')"
          [ -n "$name" ] && \
            diff_header="$(echo "$diff_header" | sed 's/@NAME/'"$name"'/')"
          [ -n "$email" ] && \
            diff_header="$(echo "$diff_header" | sed 's/@EMAIL/'"$email"'/')"
          diff_header="$(echo "$diff_header" | sed 's/@SUBJECT/'"$GIT_DIFF_SUBJECT"'/')"
          sed -i '1s/^/'"$diff_header"'\n/' "$diff_pathfile"
          sed -i '$s/$/\n'"$diff_footer"'\n/' "$diff_pathfile"
        fi
        if [[ $diff_format_paths -eq 1 && -e $diff_pathfile && -e "$diff_pathfile" ]]; then
          # modify target paths
          target_base_path="$(fn_escape "sed" "$DIFF_TARGET_BASE_PATH")"
          [ -n "$target_base_path" ] && \
            target_base_path="$(echo "$target_base_path" | sed 's/\/*$//g')\/"
          target_file="$DIFF_TARGET_FILE"
          sed -i '/^-\{3\}[ \t]*./{/\/dev\/null/b;s/\([+-]\{3\}[ \t]*\).*\/\([^\t]*\)\(.*\)$/\1a\/'"${target_base_path}${target_file:-\2}"'\3/}' "$diff_pathfile"
          sed -i '/^+\{3\}[ \t]*./{/\/dev\/null/b;s/\([+-]\{3\}[ \t]*\).*\/\([^\t]*\)\(.*\)$/\1b\/'"${target_base_path}${target_file:-\2}"'\3/}' "$diff_pathfile"
        fi
        last="$f"
        l=$((l+1))
      done
      [ -n "$target_diffs" ] && \
        echo "[info] dumped $((l-1)) diffs to '$target_diffs'" 1>&2
    fi
  fi

  # list
  echo "[info] file list:"
  date_format="%Y%b%d %H:%M:%S %z"
  field_widths=(25 $((maxlen_size+1)) $((maxlen_path+1)))
  field_order=(2 1 0)
  # header
  printf "%s%$((${field_widths[$((column_idx_file-1))]}-4))s%$((field_widths[$((column_idx_size-1))]-4))s%s %s%$((${field_widths[$((column_idx_date-1))]}-4))s\n" "path" " " " " "size" "date" " "
  # rows
  for r in "${sorted[@]}"; do
    [ $DEBUG -ge 3 ] && echo "[debug] revision: '$r' | fields: ${#fields[@]}"
    IFS=$'\t'; fields=($(echo -e "$r")); IFS="$IFSORG"
    for l in "${field_order[@]}"; do
      f="${fields[$l]}"
      if [ $l -eq $((column_idx_file-1)) ]; then
        # align left
        printf "%s%$((field_widths[$l]-${#f}))s" "$f" " "
      elif [ $l -eq $((column_idx_date-1)) ]; then
        d=$(date --date "@$f" "+$date_format")
        printf "%${field_widths[$l]}s" "$d"
      else
        printf "%${field_widths[$l]}s" "$f"
      fi
    done
    printf '\n'
  done
}

# option parsing
while [ -n "$1" ]; do
  s="$(echo "$1" | sed -n 's/^-*//gp')"
  case "$s" in
    "h"|"help") help && exit ;;
    "t"|"target") shift; target="$1" ;;
    "v"|"variants") shift; variants="$1" ;;
    "pp"|"path-precedence") shift; precedence="$1" ;;
    "nd"|"no-duplicates") remove_dupes=1 ;;
    "nz"|"no-zeros") remove_zeros=1 ;;
    "bl"|"blacklist") shift && blacklist="$1" ;;
    "g"|"group") group_by_basename=1 ;;
    "d"|"diffs") diffs=1 ;;
    "dd") target_diffs="$TARGET_DIFFS_DEFAULT" ;;
    "dump-diffs") shift; target_diffs="$1" ;;
    "dm") target_matches="$TARGET_MATCHES_DEFAULT" ;;
    "dump-matches") shift; target_matches="$1" ;;
    "ac"|"auto-clean") interactive_cleaning=0 ;;
    "dfg"|"diff-format-git") diff_format_git=1 ;;
    "dfp"|"diff-format-paths") diff_format_paths=1 ;;
    "dnp"|"diff-numeric-prefixes") diff_numeric_prefixes=1 ;;
    *) search[${#search[@]}]="$1" ;;
  esac
  shift
done
[ $DEBUG -ge 1 ] && echo "[debug] search: [${search[*]}], target: `basename $target`, diffs: $diffs: diffs target: $target_diffs, matches target: $target_matches" 1>&2

# option validation
## search
[ ${#search[@]} -eq 0 ] && help && echo "[error] no search items specified" && exit 1
## target
IFS=$'|'; targets=($(echo "$target")); IFS="$IFSORG"
l=0
while [ $l -lt ${#targets[@]} ]; do
  targets[$l]="$(fn_path_resolve "${targets[$l]}")"
  target=${targets[$l]}
  if [ ! -e "$target" ]; then
    echo "[error] invalid search target set '$target'. exiting!" && exit 1
  else
    if [ -f "$target" ]; then
      # ensure it's a supported file
      type="$(file --brief --mime-type "$target")"
      type_required="application/x-tar"
      [ "x$type" != "x$type_required" ] &&
        echo "[error] target file type '$type' unsupported, expected '$type_expected' archive" && exit
    fi
  fi
  l=$((l+1))
done

# run
fn_process

# clean up
fn_clean_up
