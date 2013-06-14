#!/bin/sh

SERVER=http://localhost/svn/
REPO_OWNER_ID=80

if [ $# -eq 0 ]; then
  echo no params!
  exit 1
fi

option=log
[ $# -gt 0 ] && [ "x$(echo "$1" | sed -n '/\(log\|add-repo\|clean-repo\|amend\|ignore\|revision\)/p')" != "x" ] && option="$1" && shift

case "$option" in
  "log")
    limit=$1 && shift
    svn log -l $limit
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
    echo `svn info 2>/dev/null | sed -n 's/^\s*Revision:\s*\([0-9]\+\)\s*/\1/p'`
    ;;

  *)
    echo "unsupported option '$option'"
    ;;

esac
