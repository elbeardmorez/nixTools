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
  echo "usage: $SCRIPTNAME [options]"
  echo -e "\noptions:"
  echo -e "\t --split\tsize (MB) to use for splitting archive into multiple volumes"
  echo -e "\t --type\t\tuse default option set for archive operation type 'add'|'update'|'extract'"
  echo -e "\t --name\t\tarchive name"
}

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
