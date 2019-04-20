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

supported_extract_formats=(
  "tar [.tar]"
  "gzip [.gz]"
  "zx [.xz]"
  "bzip2 [.bzip2/.bz2]"
  "tar (gzip/bzip2/xz) [.tar.gz/.tgz/.tar.bz2/.tbz2/.tar.xz/.txz]"
  "rar [.rar]"
  "zip [.zip]"
  "Lempel-Ziv [.Z]"
  "7zip [.7z]"
  "redhat package manager package [.rpm]"
  "WinAce [.ace]"
  "lzma [.lzma]"
  "iso9660 image [.iso]"
  "DebIan package [.deb]"
  "java package [.jar]"
)

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
      TARGETS:  one or more archive files and/or directories
                containing archive file(s)
\n$(s="";
    for f in "${supported_extract_formats[@]}"; do s="$s, $f"; done;
    echo "      support:$(echo "${s:2}" | fold -s -w64 |
    sed 's/\(.*\)/\t\1\t/')" | column -t -s$'\t')
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
  file="$1"
  case "$file" in
    *.tar.xz|*.txz|*.tar.bz|*.tbz|*.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar)
      [ "${file##*.}" = "tar" ] && \
        fn_tarmv --extract --multi-volume --name "$file" || \
        tar xvf "$file"
      ;;
    *.xz)   xz -dk "$file" ;;
    *.bz2)  bunzip2 "$file" ;;
    *.gz)   gunzip "$file" ;;
    *.zip)  unzip "$file" ;;
    *.7z)   7za x "$file" ;;
    *.Z)    uncompress "$file" ;;
    *.lzma) lzma -d -v "$file" ;;
    *.iso)  fn_extract_iso "$file" ;;
    *.rar)  unrar x "$file" ;;
    *.ace)  unace x "$file" ;;
    *.rpm)  rpm2cpio "$file" | cpio -idmv ;;
    *.deb)  fn_extract_deb "$file" ;;
    *.jar)  jar xvf "$file" ;;
    *) echo "[error] unsupported archive type '$file'" 1>&2 && return 1 ;;
  esac
}

fn_extract() {
  cwd="$(pwd)"
  path_dest=""
  if [[ "$1" == "-d" || "$1" == "--dest" ]]; then
    shift
    if [ $# -lt 2 ]; then
      help && echo "[error] not enough args!" 1>&2 && return 1
    else
      if [ ! -d "$1" ]; then
        if [ ! -f "$1" ]; then
          mkdir -p "$1"
        fi
      fi
      if [ -d "$1" ]; then
        path_dest="$1"
        shift
        [ $DEBUG -ge 1 ] && echo "[debug] destination path: '$path_dest'" 1>&2
      else
        help && echo "[error] invalid destination path: '$1'" 1>&2 && return 1
      fi
    fi
  fi

  files=("$@")
  for file in "${files[@]}"; do
    if [ -f "$file" ] ; then
      [ -z "$path_dest" ] && path_dest="$(echo "$file" | sed 's|\(.*\)/.*|\1|')"
      if [[ -d "$path_dest" && "$path_dest" != "$cwd" ]]; then
        cd "$path_dest"
        # fix file path
        [ ! -f "$file" ] && file="$cwd/$file"
      fi
      [ $DEBUG -ge 1 ] && echo "[debug] extracting '$file'" 1>&2
      fn_extract_type "$file" || return 1
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

echo "[info] done"
