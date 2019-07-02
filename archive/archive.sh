#!/bin/sh

# includes
set -e
x="$(dirname "$0")/$(basename "$0")"; [ ! -f "$x" ] && x="$(which $0)"; x="$(readlink -e "$x" || echo "$x")"
. ${x%/*}/../func_common.sh
set +e

SCRIPTNAME="${0##/*}"
DEBUG=${DEBUG:-0}

MULTIVOLUME=0
REMOVEINVALID=0
DEFAULTS=0
EXTRACT=0

default_multivolume_size=10240

declare SIZE
declare TARGET
declare NAME

# pretty names
declare -A bin_package
# bin extensions
declare -A exts_bin

# build supported maps
del="|"

## tar
bin="tar"; name="tar (gzip/bzip2/xz)"
if [ -n "$(which $bin)" ]; then
  exts=("tar" "tar.xz" "txz" "tar.bz" "tbz" "tar.bz2"
        "tbz2" "tar.gz" "tgz")
  for ext in "${exts[@]}"; do exts_bin["$ext"]="$ext$del$bin"; done
  bin_package["$bin"]="$name"
fi
## gzip
bin="gunzip"; bin_ext="gz"; name="gzip"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## bzip2
bin="bunzip2"; name="bzip"
if [ -n "$(which $bin 2>/dev/null)" ]; then
  exts=("bz" "bz2")
  for ext in "${exts[@]}"; do exts_bin["$ext"]="$ext$del$bin"; done
  bin_package["$bin"]="$name"
fi
## zip
bin="unzip"; bin_ext="zip"; name="zip"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## xz
bin="xz"; bin_ext="xz"; name="xz"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## WinRAR
bin="rar"; bin_ext="rar"; name="WinRAR"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## Lempel-Ziv
bin="uncompress"; bin_ext="Z"; name="Lempel-Ziv"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## 7-zip
bin="7za"; bin_ext="7z"; name="7-zip"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## Redhat package
bin="rpm2cpio"; bin_ext="rpm"; name="Redhat package"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## DebIan package"
bin="ar"; bin_ext="deb"; name="Debian package"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## WinAce
bin="unace"; bin_ext="ace"; name="WinAce"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## lzma (Lempel-Ziv-Markov chain)
bin="lzma"; bin_ext="lzma"; name="Lempel-Ziv-Markov"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## iso9660 image
bin="mount"; bin_ext="iso"; name="iso9660 image"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## Java jar
bin="jar"; bin_ext="jar"; name="Java package"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"
## Microsoft installer
bin="msiextract"; bin_ext="msi"; name="Microsoft installer"
[ -n "$(which $bin 2>/dev/null)" ] && \
  exts_bin["$bin_ext"]="$bin_ext$del$bin" && \
  bin_package["$bin"]="$name"


IFS=$'\n'; res=($(fn_reversed_map_values "$del" "${exts_bin[@]}")); IFS="$IFSORG"
declare -A bin_exts
for kvp in "${res[@]}"; do k="${kvp%%${del}*}"; bin_exts["$k"]="$kvp"; done

if [ $DEBUG -ge 5 ]; then
  echo -e "\n${CLR_HL}[debug] exts_bin:${CLR_OFF}"
  for s in "${exts_bin[@]}"; do echo "$s"; done
  echo -e "\n${CLR_HL}[debug] bin_exts:${CLR_OFF}"
  for s in "${bin_exts[@]}"; do echo "$s"; done
  echo ""
fi

fn_supported_extract_formats() {
  declare del="$1";
  declare s="";
  for kvp in "${bin_exts[@]}"; do
    k="${kvp%%${del}*}"
    v=".$(echo "${kvp#*${del}}" | sed 's/'$del'/\/./g')"
    s="$s, "${bin_package["$k"]}" [$v]"
  done
  echo "${s:2}"
}

help() {
  echo -e "SYNTAX: ${CLR_HL}$SCRIPTNAME [-h] [MODE] [OPTIONS]${CLR_OFF}
\n  -h, --help  : print this help information
\n  MODE:
\n    ${CLR_HL}a, add${CLR_OFF}:  create a tar archive
\n      SYNTAX: ${CLR_HL}$SCRIPTNAME --add --name NAME --target TARGET [OPTIONS]${CLR_OFF}
\n      NAME:  achive name
      TARGET:  path to files for addition
      OPTIONS:
        -mv, --multi-volume  : assume multi-volume archive
        -s, --split  : max size (MB) to use for splitting archive into
                       multiple volumes
\n      support: tar only
\n    ${CLR_HL}u, update${CLR_OFF}:  update a tar archive
\n      SYNTAX: ${CLR_HL}$SCRIPTNAME --update --name NAME --target TARGET [OPTIONS]${CLR_OFF}
\n      NAME:  achive name
      TARGET:  path to files for addition / update
      OPTIONS:
        -mv, --multi-volume  : assume multi-volume archive
\n      support: tar only
\n    ${CLR_HL}x, extract${CLR_OFF}:  extract [multiple] archive files
\n      SYNTAX: ${CLR_HL}$SCRIPTNAME --extract [OPTIONS] TARGETS${CLR_OFF}
\n      OPTIONS:
        -d, --dest PATH  : extract to PATH
        -a, --as TYPE  : override extention based deduction of archive
                         type
      TARGETS:  one or more archive files and/or directories
                containing archive file(s)
\n$(echo "      support:$(echo "$(fn_supported_extract_formats $del)" |
                          fold -s -w64 |  sed 's/\(.*\)/\t\1\t/')" |
                          column -t -s$'\t')
"
}

fn_tarmv() {
  # parse args
  args=("$@")
  args2=""
  l=0
  while [ $l -lt "${#args[@]}" ]; do
    OPT="${args[l]}"
    [ $DEBUG -ge 1 ] && echo "[debug] opt $l: $OPT" 1>&2
    case $OPT in
      "--type")
        DEFAULTS=1
        l=$((l + 1))
        OPT="${args[l]}"
        [ $DEBUG -ge 1 ] && echo "[debug] type set: $OPT" 1>&2
        case $OPT in
          "add")
            args2=("${args2[@]}" "--create")
            ;;
          "update")
            REMOVEINVALID=1
            args2=("${args2[@]}" "--update")
            ;;
          "extract")
            EXTRACT=1
            args2=("${args2[@]}" "--extract")
            ;;
      "-n"|"--name"|"-f"|"--file")
        l=$((l + 1))
        OPT="${args[l]}"
        [ "${OPT:$((${#OPT} - 4)):4}" != ".tar" ] && OPT="$OPT.tar"
        NAME="$OPT"
        args2=("${args2[@]}" "--file" "$OPT")
        ;;
      "-t"|"--target")
        # test and set target if specified
        if [ $((l + 1)) -lt ${#args[@]} ]; then
          OPT="${args[$((l + 1))]}"
          if [ "${OPT:0:1}" != "-" ]; then
            # consume arg
            l=$((l + 1))
            # assume directory
            if [ -d "$OPT" ]; then
              TARGET="$OPT"
              args2=("${args2[@]}" "--directory" "$TARGET")
            else
              fn_decision "[user] create TARGET directory '$OPT'?" 1>/dev/null || return 1
              TARGET="$OPT"
              mkdir -p "$TARGET"
              args2=("${args2[@]}" "--directory" "$TARGET")
            fi
          fi
        fi
        ;;
      "-mv"|"--multi-volume"|"-F"|"--info-script"|"-M")
        MULTIVOLUME=1
        ;;
      "-s"|"--split"|"-L"|"--tape-length")
        MULTIVOLUME=1
        SIZE=$default_multivolume_size
        if [ -n "$(echo "$((l + 1))" | sed -n '/^[0-9.]\+$/p')" ]; then
          l=$((l + 1))
          SIZE=${args[l]}
          [ "$OPT" = "--split" ] && \
            SIZE=$((OPT * 1024)) && SIZE=${SIZE%%.*}  # size in MB
        fi
        [ $DEBUG -ge 1 ] && echo "[debug] max size: $SIZE kb" 1>&2
        ;;
      "-u"|"--update")
        REMOVEINVALID=1
        ;;
      "-x"|"--extract")
        EXTRACT=1
        args2=("${args2[@]}" "$OPT")
        ;;
          *)
            help && echo "[error] unsupported option arg '$OPT' for option '--type'" 1>&2 && return 1
            ;;
        esac
        ;;
      *)
        args2=("${args2[@]}" "$OPT")
        ;;
    esac
    l=$((l + 1))
  done
  # trim initial empty arg
  args2=(${args2[@]:1:${#args2[@]}})

  # ensure non-optional parameters were set
  [ -z "$NAME" ] && help && echo "[error] non-optional parameter 'NAME' missing" 1>&2 && return 1
  [[ $EXTRACT == 0 && -z "$TARGET" ]] && help && echo "[error] non-optional parameter 'TARGET' missing" 1>&2 && return 1

  # create tar multi-volume script
  MVTARSCRIPT=/tmp/tar.multi.volume
  cat > $MVTARSCRIPT << EOF
#!/bin/sh
TAR_NAME=\${name:-\$TAR_ARCHIVE}
if [ "\${TAR_NAME:\$[\${#TAR_NAME}-4]:4}" = ".tar" ]; then
  TAR_NAME="\${TAR_NAME:0:\$[\${#TAR_NAME}-4]}"
fi
TAR_BASE=\$TAR_NAME
TAR_BASE=\`expr \$TAR_BASE : '\\(.*\\)-.*'\`
if [ "x\$TAR_BASE" = "x" ]; then
  TAR_BASE=\$TAR_NAME
fi
echo volume \$TAR_VOLUME of archive \'\$TAR_BASE\'
case \$TAR_SUBCOMMAND in
  -c|-u)
    ;;
  -d|-x|-t)
    test -r \$TAR_BASE-\$TAR_VOLUME".tar" || exit 1
    ;;
  *)
    exit 1
    ;;
esac
echo \$TAR_BASE-\$TAR_VOLUME".tar" >&\$TAR_FD
EOF
  chmod +x "$MVTARSCRIPT"

  if [ $DEFAULTS -eq 1 ]; then
    args2=("--verbose" "--seek" "${args2[@]}")
    if [ "x$TARGET" = "x" ]; then
      TARGET=/
    fi
    args2=("${args2[@]}" "--directory" $TARGET)
  fi
  if [ $MULTIVOLUME -eq 1 ]; then
    [[ $EXTRACT -eq 0 && -n "$SIZE" ]] && \
      args2=("--tape-length" "$SIZE" "${args2[@]}")
    args2=("--multi-volume" "--info-script" "$MVTARSCRIPT" "${args2[@]}")
  fi

  # updating..
  if [ $REMOVEINVALID -eq 1 ]; then
    # get invalid
    TEMP=$(fn_temp_file)
    [ $DEBUG -ge 1 ] && echo "[debug] tar --diff ${args2[*]}" 1>&2
    tar "--diff" "${args2[@]}" 2>&1 | grep -i 'no such file' | awk -F: '{gsub(" ","",$2); print $2}' > $TEMP
    if [ $(wc -l $TEMP | sed 's|^[ ]*\([0-9]*\).*$|\1|g') -gt 0 ]; then
      # delete invalid (non-existent on host) files from archive
      tar "--delete" "--files-from" "$TEMP" "${args2[@]}"
    fi
    rm $TEMP
  fi

  #tar
  tar "${args2[@]}"
}

fn_extract_iso() {
  res=1
  mount_point="$(fn_temp_dir)"
  if [ -d "$file" ]; then
    mount -t iso9660 -o ro "$1" "$mount_point"
    cp -R "$mount_point"/* "./" 2>/dev/null
    res=$?
    umount "$file" && rmdir "$mount_point"
  fi
  return $res
}

fn_extract_deb() {
  declare files
  CWD=$PWD/
  if [ -n "$(ar t "$1" | sed -n '/^debian-binary$/p')" ]; then
    # shift to prevent semi-bomb
    file="$(echo "${1##*/}" | sed 's|.deb$||')"
    mkdir "$file" 2>/dev/null
    cd "$file"
  fi
  ar xv "$CWD$1"
  files=(data.tar.*)
  [ ${#files[@]} -gt 0 ] && fn_extract_type "${files[@]}"
}

fn_extract_type() {
  declare file
  declare override
  declare type
  file="$1" && shift
  override="$1"
  type="$file" && [ -n "$override" ] && type="$override"
  fext="${type##*.}"
  case "$type" in
    *.tar.xz|*.txz|*.tar.bz|*.tbz|*.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar)
      [ "" = "tar" ] && \
        fn_tarmv --extract --multi-volume --name "$file" || \
        tar xvf "$file"
      ;;
    *.iso) fn_extract_iso "$file" ;;
    *.deb) fn_extract_deb "$file" ;;
    *)
      ext_bin="${exts_bin["$fext"]}"
      bin="${ext_bin#*$del}"
      case "$fext" in
        "xz")   $bin -dk "$file" ;;
        "bz2")  $bin "$file" ;;
        "gz")   $bin "$file" ;;
        "zip")  $bin "$file" ;;
        "7z")   $bin "$file" ;;
        "Z")    $bin "$file" ;;
        "lzma") $bin -d -v "$file" ;;
        "rar")  $bin x "$file" ;;
        "ace")  $bin x "$file" ;;
        "rpm")  $bin "$file" | cpio -idmv ;;
        "jar")  $bin xvf "$file" ;;
        "msi")  $bin "$file" ;;
      esac
  esac
}

fn_extract() {
  declare cwd
  declare path_dest
  declare override
  declare -a files
  declare ext
  cwd="$(pwd)"
  path_dest=""
  override=""
  while [ -n "$1" ]; do
    arg="$(echo "$1" | sed 's/^[ ]*-*//')"
    case "$arg" in
      "d"|"dest")
        shift
        if [ $# -lt 2 ]; then
          help && echo "[error] not enough args!" 1>&2 && return 1
        else
          [ ! -e "$1" ] && mkdir -p "$1"
          if [ -d "$1" ]; then
            path_dest="$1"
            shift
            [ $DEBUG -ge 1 ] && echo "[debug] destination path: '$path_dest'" 1>&2
          else
            help && echo "[error] invalid destination path: '$1'" 1>&2 && return 1
          fi
        fi
        ;;

      "a"|"as")
        shift
        override="$1"
        # ensure validity, extension or binary translated to extension
        valid="${exts_bin["$override"]}"
        [ -z "$valid" ] && valid="${bin_exts["$override"]}"
        [ -n "$valid" ] && \
          override="${valid%%${del}*}" || \
          echo "[error] type override '$override', unsupported or" \
               "missing binary"
        ;;

      *)
        files[${#files[@]}]="$arg"
        ;;
    esac
    shift
  done

  for file in "${files[@]}"; do
    if [ -f "$file" ] ; then
      [ -z "$path_dest" ] && path_dest="$(echo "$file" | sed 's|\(.*\)/.*|\1|')"
      if [[ -d "$path_dest" && "$path_dest" != "$cwd" ]]; then
        cd "$path_dest"
        # fix file path
        [ ! -f "$file" ] && file="$cwd/$file"
      fi
      if [ -z "$override" ]; then
        IFS="."; fps=($(echo "$file")); IFS="$IFSORG"
        [ ${#fps[@]} -eq 1 ] && \
          echo "[info] skipping file '$file', primitive type deduction" \
               "is based on known file extensions" && continue
        if [ ${#fps[@]} -gt 2 ]; then
          ext="${fps[$((${#fps[@]} - 2))]}.${fps[$((${#fps[@]} - 1))]}"
          [ $DEBUG -ge 1 ] && echo "[debug] testing ext: '$ext'"
          valid_ext="${exts_bin["$ext"]}"
        fi
        if [ -z "$valid_ext" ]; then
          ext="${fps[$((${#fps[@]} - 1))]}"
          [ $DEBUG -ge 1 ] && echo "[debug] testing ext: '$ext'"
          valid_ext="${exts_bin["$ext"]}"
        fi
        [ -z "$valid_ext" ] && \
          echo "[info] skipping file '$file'," \
               "unsupported type / missing binary" && continue
      fi
      [ $DEBUG -ge 1 ] && echo "[debug] extracting '$file'" 1>&2
      fn_extract_type "$file" "$override" || return 1
    else
      echo "[info] skipping invalid file: '$file'"
    fi
    cd "$cwd"
  done
}

arg="" && [ $# -gt 0 ] && arg="$(echo "$1" | sed 's/^[ ]*-*//')"
case "$arg" in
  ""|"h"|"help") help && exit ;;
  *)
    [ $# -lt 2 ] && help && echo "[error] not enough args!" 1>&2 && exit 1
    case "$arg" in
      "a"|"add"|"u"|"update") shift; fn_tarmv --type "$arg" "$@" ;;
      "x"|"extract") shift; fn_extract "$@" ;;
      *) help && echo "[error] unsupported mode '$1'" 1>&2 && exit 1 ;;
    esac
esac
