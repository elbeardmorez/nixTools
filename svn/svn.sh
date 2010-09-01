#!/bin/sh

SERVER=http://localhost/svn/
REPO_OWNER_ID=80

if [ $# -eq 0 ]; then
  echo no params!
  exit 1
fi

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
