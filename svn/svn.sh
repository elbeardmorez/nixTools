#!/bin/sh
DEBUG=${DEBUG:-0}
TEST=${TEST:-0}
IFSORG="$IFS"

SERVER=http://localhost/svn/
REPO_OWNER_ID=80

function fnLog() {
  # validate arg(s)
  rev1=-1 && [ $# -gt 0 ] && rev1="$1" && shift
  [ "x$(echo $rev1 | sed -n '/^[-+r]\?[0-9]\+$/p')" == "x" ] &&
    echo "[error] invalid revision arg '$rev1'" && exit 1
  rev2="" && [ $# -gt 0 ] &&
    [ "x$(echo "$1" | sed -n '/^[-+r]\?[0-9]\+$/p')" != "x" ] &&
    rev2="$1" && shift

  # tokenise
  IFS=$'\n' && tokens=(`echo " $rev1 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p'`) && IFS="$IFSORG"
  rev1prefix=`echo ${tokens[0]} | tr -d ' '`
  rev1=`echo ${tokens[1]} | tr -d ' '`
  rev1suffix=`echo ${tokens[2]} | tr -d ' '`
  tokens=("" "" "")
  [ "x$rev2" != "x" ] &&
    IFS=$'\n' && tokens=(`echo " $rev2 " | sed -n 's/\(\s*[-+r]\?\|\s*\)\([0-9]\+\)\(.*\)$/\1\n\2\n\3/p'`) && IFS="$IFSORG"
  rev2prefix=`echo ${tokens[0]} | tr -d ' '`
  rev2=`echo ${tokens[1]} | tr -d ' '`
  rev2suffix=`echo ${tokens[2]} | tr -d ' '`
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fnLog] rev1: '$rev1prefix|$rev1|$rev1suffix' `[ "x$rev2" != "x" ] && echo "rev2: '$rev2prefix|$rev2|$rev2suffix'"`" 1>&2
  # mod
  if [ "x$rev1prefix" == "x" ]; then
    [ $rev1 -gt 25 ] && rev1prefix="-r " || rev1prefix="-"
  fi
  [[ "x$rev1prefix" == "x" && $rev1 -gt 25 ]] && rev1prefix="-"
  [ "x$rev1prefix" == "x+" ] && rev1prefix="-r "
  [ "x$rev1prefix" == "xr" ] && rev1prefix="-r "
  if [ "x$rev2" != "x" ]; then
    rev1suffix=":"
    [[ "x$rev1prefix" != "x-" && $rev1 -gt $rev2 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    [[ "x$rev1prefix" == "x-" && $rev2 -gt $rev1 ]] && revX=$rev1 && rev1=$rev2 && rev2=$revX
    rev2prefix=""
  fi
  if [ "x$rev2" == "x" ]; then
    [[ "x$rev1prefix" == "x-" || "x$rev1prefix" == "x" ]] && rev1prefix="-l "
  else
    if [ "x$rev1prefix" == "x-" ]; then
      # convert to revision numbers
      base=`fnRevision`
      [ "x$base" == "x" ] && base=0
      rev2prefix=""
      rev1=$[$base-$rev1+1]
      rev2=$[$base-$rev2+1]
    fi
    rev1prefix="-r "
  fi
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fnLog] rev1: '$rev1prefix|$rev1|$rev1suffix' `[ "x$rev2" != "x" ] && echo "rev2: '$rev2prefix|$rev2|$rev2suffix'"`" 1>&2
  [ $DEBUG -gt 0 ] &&
    echo "[debug|fnLog] svn log $rev1prefix$rev1$rev1suffix$rev2prefix$rev2$rev2suffix" "$@" 1>&2
  [ $TEST -eq 0 ] && svn log $rev1prefix$rev1$rev1suffix$rev2prefix$rev2$rev2suffix "$@"
}

function fnRevision() {
  echo `svn info 2>/dev/null | sed -n 's/^\s*Revision:\s*\([0-9]\+\)\s*/\1/p'`
}

if [ $# -eq 0 ]; then
  echo no params!
  exit 1
fi

option=log
[ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(log\|add-repo\|clean-repo\|amend\|ignore\|revision\|test\)/p')" != "x" ] && option="$1" && shift

case "$option" in
  "log")
    [ $# -eq 0 ] && fnLog 1 || fnLog "$@"
    ;;

  "add-repo")
    target=$1
    if [ "$(echo "$target" | awk '{print substr($0, length($0))}')" = "/" ]; then
      target=$(echo "$target" | awk '{print substr($0, 1, length($0) - 1)}')
    fi

    repo=$(echo "$target" | sed 's/.*\/\(.*\)/\1/')

    if ! [ -d $target ]; then
      mkdir -p $target
      if [ $? -ne 0 ]; then
        echo cannot create $target
        exit 1
      fi
    fi

    if [ "$(ls -A $target)" ]; then
      echo -n "repo path is not empty, delete contents of $target? [y/n]"
      declare result
      while read -es -n 1 result ; do
        if [ "$result" = "y" ]; then
          break
        elif [ "$result" = "n" ]; then
          exit 1
        fi
      done
      if [ "$result" = "y" ]; then
        rm -R $target/*
      else
        exit 1
      fi
    fi

    # cd necessary as svnadmin doesn't handle relative paths
    cwd=$(pwd)
    cd $target
    svnadmin create --fs-type fsfs $target
    chown -R $REPO_OWNER_ID:$REPO_OWNER_ID $target
    chmod -R ug+rw $target

    rm -rf temp
    svn co $SERVER$repo temp
    svn mkdir temp/branches temp/tags temp/trunk
    svn ci -m "[add] repository structure" ./temp
    rm -rf temp
    ;;

  "clean-repo")
    target=$1
    if ! [ -d $target ]; then
      echo "'$target' is not a directory"
      exit 1
    fi
    matches=($(find $target -name *.svn))
    if [ ${#matches[@]} -eq 0 ]; then
      echo "no '.svn' directories found under specified workspace"
    else
      for d in ${matches[@]}; do
        echo "found a '.svn' directory at '$d'"
      done
      echo -n "remove all? [y/n]"
      read -es -n1 result
      if [ "$result" = "y" ]; then
        for d in ${matches[@]}; do
          rm -rf $d
          if [[ $? -eq 0 && ! -d $d ]]; then
            echo "removed '$d'"
          else
            echo "failed to remove '$d'"
            exit 1
          fi
        done
      fi
    fi
    ;;

  "amend")
    revision=$1 && shift
    svn propedit --revprop -r $revision svn:log
    ;;

  "ignore")
    if [ ! -d $(pwd)/.svn ]; then
      echo $(pwd) is not under source control
      exit 1
    fi

    declare list
    for arg in $@; do
      if [ ${#list} -eq 0 ]; then
        list="$arg"
      else
        list=$list\$\'\\n\'$arg
      fi
    done
    eval "svn propset svn:ignore $list ."

    sleep 1
    echo "svn:ignore set:"
    svn propget svn:ignore
    ;;

  "revision")
    fnRevision
    ;;

  "test")
    type=${1:-log}
    case "$type" in
      "log")
        TEST=1
        echo ">log r12 r15" && fnLog r12 r15
        echo ">log r15 r12" && fnLog r15 r12
        echo ">log 12 15" && fnLog 12 15
        echo ">log -12 -15" && fnLog -12 -15
        echo ">log -15 -12" && fnLog -15 -12
        echo ">log -10" && fnLog -10
        echo ">log 10" && fnLog 10
        echo ">log 30" && fnLog 30
        echo ">log -30" && fnLog -30
        echo ">log +10" && fnLog +10
        echo ">log r10" && fnLog r10
        echo ">log r10 /path" && fnLog r10 /path
        echo ">log r10 r15 /path" && fnLog r10 r15 /path
        ;;
    esac
    ;;

  *)
    echo "unsupported option '$option'"
    ;;

esac
