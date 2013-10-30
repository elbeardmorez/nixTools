#!/bin/sh

SUPPORT_FUNCTIONS=../func_common.sh
if [ -e $SUPPORT_FUNCTIONS ]; then
  . $SUPPORT_FUNCTIONS
else
  echo error: no support functions available at \'$SUPPORT_FUNCTIONS\'
  exit 1
fi

SCRIPTNAME=${0##/*}

MULTIVOLUME=0
REMOVEINVALID=0
DEFAULTS=0
EXTRACT=0
SIZE=
TARGET=""
NAME=""

function help()
{
  echo "usage: $SCRIPTNAME [mode] [type] [options] [archive(s)]"
  echo -e "\nmode:"
  echo -e "\n add:  creation / addition [tar only]"

  echo -e "\noptions:"
  echo -e "\t --split\tsize (MB) to use for splitting archive into multiple volumes"
  echo -e "\t --name\t\tarchive name"
  echo -e "\n update:  [tar only]"
  echo -e "\n extract:  extract [multiple] archive files"
  echo -e "\n  options:"
  echo -e "\t   [-t 'target directory']  : extract to target directory"
  echo -e "\t  'archive(s)  : archive files / directory containing archive files'\n"
}
function tarmv()
{
#parse args
args=("$@")
args2=""
l=0
while [ $l -lt "${#args[@]}" ]; do
  OPT="${args[l]}"
  echo "opt $l: $OPT"
  case $OPT in
    "-C"|"--target")
      #test and set target if specified
      if [ $[l+1] -lt ${#args[@]} ]; then
        OPT="${args[$[l+1]]}"
        if [ ! "${OPT:0:1}" == "-" ]; then
          #consume arg
          l=$[$l+1]
          #assume directory
          if [ -d "$OPT" ]; then
            TARGET="$OPT"
            args2=( "${args2[@]}" "--directory" $TARGET )
          else
            echo -n "create TARGET directory '$OPT'?"
            result
            read -n 1 result
            if [[ "$result" == "y" || "$result" == "Y" ]]; then
              echo $result
              TARGET="$OPT"
              mkdir -p "$TARGET"
              args2=( "${args2[@]}" "--directory" $TARGET )
            else
              echo ""
            fi
          fi
        fi
      fi
      ;;
    "-F"|"--info-script"|"-M"|"--multi-volume"|"--multi")
      MULTIVOLUME=1
      ;;
    "-L"|"--tape-length")
      l=$[$l+1]
      MULTIVOLUME=1
      SIZE=${args[l]}
      #echo size $SIZE
      ;;
    "--split")
      l=$[$l+1]
      OPT="${args[l]}"
      MULTIVOLUME=1
      #size in MB
      SIZE=$(echo $OPT*1024 | bc)
      SIZE=${SIZE%%.*}
      ;;
    "-u"|"--update")
      REMOVEINVALID=1
      ;;
    "-x"|"--extract")
      EXTRACT=1
      args2=( "${args2[@]}" "$OPT" )
      ;;
    "--name")
      l=$[$l+1]
      OPT="${args[l]}"
      if [ ! "${OPT:$[${#OPT}-4]:4}" == ".tar" ]; then
        OPT="$OPT.tar"
      fi
      NAME=$OPT
      args2=( "${args2[@]}" "--file" $OPT )
      ;;
    "--type")
      echo type
      DEFAULTS=1
      l=$[$l+1]
      OPT="${args[l]}"
      case $OPT in
        "add")
          args2=( "${args2[@]}" "--create" )
          ;;
        "update")
          REMOVEINVALID=1
          args2=( "${args2[@]}" "--update" )
          ;;
        "extract")
          EXTRACT=1
          args2=( "${args2[@]}" "--extract" )
          ;;
        *)
          echo "error: unsupported option arg '$OPT' for option '--type'"
          help
          exit 1
          ;;
      esac
      ;;
    "-f"|"--file")
      ;;
    *)
      args2=( "${args2[@]}" "$OPT" )
      ;;
  esac
  l=$[$l+1]
done
#trim initial empty arg
args2=( ${args2[@]:1:${#args2[@]}} )

#ensure non-optional parameters were set
if [ "x$NAME" == "x" ]; then 
  help
  echo error: non-optional parameter 'NAME' missing
  exit 1
fi

#create tar multi-volume script
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
  args2=( "--verbose" "--seek" "${args2[@]}" )
  if [ "x$TARGET" == "x" ]; then
    TARGET=/
  fi
  args2=( "${args2[@]}" "--directory" $TARGET )
fi
if [ $MULTIVOLUME -eq 1 ]; then
  if [[ $DEFAULTS -eq 1 && $EXTRACT -eq 0 ]]; then
    if [ "x$SIZE" == "x" ]; then
      SIZE=10240
    fi
    args2=( "--tape-length" "$SIZE" "${args2[@]}" )
  fi
  args2=( "--multi-volume" "--info-script" "$MVTARSCRIPT" "${args2[@]}" )
fi

#updating..
if [ $REMOVEINVALID -eq 1 ]; then
  #get invalid
  TEMP=$(tempfile)
  echo tar "--diff" "${args2[@]}"
  tar "--diff" "${args2[@]}" 2>&1 | grep -i 'no such file' | awk -F: '{gsub(" ","",$2); print $2}' > $TEMP
  if [ $(wc -l $TEMP | sed 's|^[ ]*\([0-9]*\).*$|\1|g') -gt 0 ]; then
    #delete invalid (non-existent on host) files from archive
    tar "--delete" "--files-from" "$TEMP" "${args2[@]}"
  fi
  rm $TEMP
fi

#tar
tar "${args2[@]}"
}
function extractiso()
{
  result=1
  set +e
  file=$(tempfile) && rm $file && mkdir -p $file || return 1
  if [ -d $file ]; then
    mount -t iso9660 -o ro "$1" $file
    result=$( cp -R $file/* . )
    umount $file && rmdir $file
  fi
  set -e
  echo $result  
}
function extractdeb()
{
  CWD=$PWD/
  if [ ! "x$(ar t $1 | sed -n '/^debian-binary$/p')" == "x" ]; then
    #shift to prevent semi-bomb
    file=$(echo "${1##*/}" | sed 's|.deb$||') 
    mkdir "$file" 2>/dev/null
    cd "$file"
  fi
  ar xv "$CWD$1"
  if [ -f data.tar.* ]; then extract_ data.tar.*; fi  
}
function extracttype ()
{
  case "$1" in
   *.tar.xz)        xz -dk "$1" | tar xvf - ;;
   *.tar.bz2|*.tbz) tar xjf "$1" ;;
   *.tar.gz)        tar xzf "$1" ;;
   *.bz2)           bunzip2 "$1" ;;
   *.rar)           unrar x "$1" ;;
   *.gz)            gunzip "$1" ;;
   *.tar)           tarmv --extract --multi --name "$1" ;;
   *.txz)           xz -dk "$1" | tar xvf - ;;
   *.tbz2)          tar xjf "$1" ;;
   *.tgz)           tar xzf "$1" ;;
   *.zip)           unzip "$1" ;;
   *.Z)             uncompress "$1" ;;
   *.7z)            7za x "$1" ;;
   *.rpm)           rpm2cpio "$1" | cpio -idmv ;;
   *.ace)	          unace x "$1" ;;
   *.lzma)	        lzma -d -v "$1" ;;
   *.iso)	          extractiso "$1" ;;
   *.deb)           extractdeb "$1" ;;
   *.jar)           jar xvf "$1" ;;
   *) echo "unsupported archive type '$1'" ;;
  esac
}
function extract()
{
  dirorig="$(pwd)"
  dirtarget=""
  if [ "$1" == "-t" ]; then
    shift
    if [ $# -lt 2 ]; then
      echo not enough args!
      help
      exit 1
    else
      if ! [ -d "$1" ]; then
        if ! [ -f "$1" ]; then
          mkdir -p "$1"
        fi
      fi
      if [ -d "$1" ]; then   
        dirtarget="$1"
        shift
        echo "target directory: '$dirtarget'"
      else
        echo "invalid target directory: '$1'"
        help
        exit 1
      fi
    fi
  fi
  files=("$@")
  for file in "${files[@]}"; do
    if [ -f "$file" ] ; then
      if [ "x$dirtarget" == "x" ]; then
        dirtarget=$(echo "$file" | sed 's|\(.*\)/.*|\1|')
      fi
      if [ -d "$dirtarget" ]; then
        if ! [ "$dirtarget" == $(pwd) ]; then 	  
          cd "$dirtarget"
          if ! [ -f "$file" ] ; then
            #obviously it was a file in the old pwd
            file=$dirorig/$file	
          fi
        fi
      fi
      echo extracting "$file"
      extracttype "$file"
    else
      echo "'$file' is not a valid file"
    fi
    cd "$dirorig"
  done
}

if [ $# -lt 2 ]; then
  echo not enough args!
  help
  exit 1
fi
case "$1" in
  "add"|"update") tarmv --type "$@" ;;
  "extract") shift; extract "$@" ;;
   *) help; echo "unsupported mode '$1'" ;;
esac
echo done
