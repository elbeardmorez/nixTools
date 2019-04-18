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

declare SIZE
declare TARGET
declare NAME

help() {
  echo "usage: $SCRIPTNAME [mode] [type] [options] [archive(s)]"
  echo -e "\nmode:"
  echo -e "\n add:  creation / addition [tar only]"

  echo -e "\n  options:"
  echo -e "\t   --split\tsize (MB) to use for splitting archive into multiple volumes"
  echo -e "\t   --name\t\tarchive name"
  echo -e "\n update:  [tar only]"
  echo -e "\n extract:  extract [multiple] archive files"
  echo -e "\n  options:"
  echo -e "\t   [-t 'target directory']  : extract to target directory"
  echo -e "\t   'archive(s)  : archive files / directory containing archive files'\n"
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
      "-C"|"--target")
        # test and set target if specified
        if [ $((l + 1)) -lt ${#args[@]} ]; then
          OPT="${args[$((l + 1))]}"
          if [ ! "${OPT:0:1}" == "-" ]; then
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
      "-F"|"--info-script"|"-M"|"--multi-volume"|"--multi")
        MULTIVOLUME=1
        ;;
      "-L"|"--tape-length")
        l=$((l + 1))
        MULTIVOLUME=1
        SIZE=${args[l]}
        [ $DEBUG -ge 1 ] && echo "[debug] max size: $SIZE" 1>&2
        ;;
      "--split")
        l=$((l + 1))
        OPT=${args[l]}
        MULTIVOLUME=1
        # size in MB
        SIZE=$(echo $OPT*1024 | bc)
        SIZE=${SIZE%%.*}
        ;;
      "-u"|"--update")
        REMOVEINVALID=1
        ;;
      "-x"|"--extract")
        EXTRACT=1
        args2=("${args2[@]}" "$OPT")
        ;;
      "--name")
        l=$((l + 1))
        OPT="${args[l]}"
        [ "${OPT:$((${#OPT} - 4)):4}" != ".tar" ] && OPT="$OPT.tar"
        NAME="$OPT"
        args2=("${args2[@]}" "--file" "$OPT")
        ;;
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
          *)
            help && echo "[error] unsupported option arg '$OPT' for option '--type'" 1>&2 && return 1
            ;;
        esac
        ;;
      "-f"|"--file")
        # no-op
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
  [ "x$NAME" == "x" ] && help && echo "[error] non-optional parameter 'NAME' missing" 1>&2 && return 1

  # create tar multi-volume script
  MVTARSCRIPT=/tmp/tar.multi.volume
  cat > $MVTARSCRIPT << EOF
#!/bin/sh
TAR_NAME=\${name:-\$TAR_ARCHIVE}
if [ "\${TAR_NAME:\$[\${#TAR_NAME}-4]:4}" == ".tar" ]; then
  TAR_NAME="\${TAR_NAME:0:\$[\${#TAR_NAME}-4]}"
fi
TAR_BASE=\$TAR_NAME
TAR_BASE=\`expr \$TAR_BASE : '\\(.*\\)-.*'\`
if [ "x\$TAR_BASE" == "x" ]; then
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
    if [ "x$TARGET" == "x" ]; then
      TARGET=/
    fi
    args2=("${args2[@]}" "--directory" $TARGET)
  fi
  if [ $MULTIVOLUME -eq 1 ]; then
    if [[ $DEFAULTS -eq 1 && $EXTRACT -eq 0 ]]; then
      if [ "x$SIZE" == "x" ]; then
        SIZE=10240
      fi
      args2=("--tape-length" "$SIZE" "${args2[@]}")
    fi
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
  case "$1" in
   *.tar.xz)        tar xvJf "$1" ;;
   *.tar.bz2|*.tbz) tar xjf "$1" ;;
   *.tar.gz)        tar xzf "$1" ;;
   *.bz2)           bunzip2 "$1" ;;
   *.xz)            xz -dk "$1" ;;
   *.rar)           unrar x "$1" ;;
   *.gz)            gunzip "$1" ;;
   *.tar)           fn_tarmv --extract --multi --name "$1" ;;
   *.txz)           tar xvJf "$1" ;;
   *.tbz2)          tar xjf "$1" ;;
   *.tgz)           tar xzf "$1" ;;
   *.zip)           unzip "$1" ;;
   *.Z)             uncompress "$1" ;;
   *.7z)            7za x "$1" ;;
   *.rpm)           rpm2cpio "$1" | cpio -idmv ;;
   *.ace)           unace x "$1" ;;
   *.lzma)          lzma -d -v "$1" ;;
   *.iso)           fn_extract_iso "$1" ;;
   *.deb)           fn_extract_deb "$1" ;;
   *.jar)           jar xvf "$1" ;;
   *) echo "[error] unsupported archive type '$1'" 1>&2 && return 1 ;;
  esac
}

fn_extract() {
  dirorig="$(pwd)"
  dirtarget=""
  if [ "$1" == "-t" ]; then
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
        dirtarget="$1"
        shift
        [ $DEBUG -ge 1 ] && echo "[debug] target directory: '$dirtarget'" 1>&2
      else
        help && echo "[error] invalid target directory: '$1'" 1>&2 && return 1
      fi
    fi
  fi

  files=("$@")
  for file in "${files[@]}"; do
    if [ -f "$file" ] ; then
      if [ "x$dirtarget" == "x" ]; then
        dirtarget="$(echo "$file" | sed 's|\(.*\)/.*|\1|')"
      fi
      if [ -d "$dirtarget" ]; then
        if ! [ "$dirtarget" == $(pwd) ]; then
          cd "$dirtarget"
          if ! [ -f "$file" ] ; then
            # obviously it was a file in the old pwd
            file="$dirorig/$file"
          fi
        fi
      fi
      [ $DEBUG -ge 1 ] && echo "[debug] extracting '$file'" 1>&2
      fn_extract_type "$file" || return 1
    else
      echo "[info] skipping invalid file: '$file'"
    fi
    cd "$dirorig"
  done
}

[ $# -lt 2 ] && help && echo "[error] not enough args!" 1>&2 && exit 1

case "$1" in
  "add"|"update") fn_tarmv --type "$@" ;;
  "extract") shift; fn_extract "$@" ;;
  *) help && echo "[error] unsupported mode '$1'" 1>&2 && exit 1 ;;
esac

echo "[info] done"
