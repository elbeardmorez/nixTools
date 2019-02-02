#!/bin/sh
SCRIPTNAME="${0##*/}"

IFSORG="$IFS"
DEBUG=${DEBUG:-0}
PKGNAME=
BUILDTYPE=user
WGETOPTS="--no-check-certificate"
REPOMULTILIB=current
URLMULTILIB=http://slackware.com/~alien/multilib/
REPOSLACKBUILDS=14.2
URLSLACKBUILDS=http://slackbuilds.org/slackbuilds/
REPOSOURCE=${REPOSOURCE:-current}
ARCH2=${ARCH:-"$(uname -m)"} && [ ${ARCH2:$[${#ARCH2}-2]:2} == 64 ] && ARCHSUFFIX=64 && ARCH2=_x86_64
URLSOURCE=https://mirror.slackbuilds.org/slackware/slackware$ARCHSUFFIX-$REPOSOURCE/source
PKGLISTLOCAL=/var/lib/slackpkg/PACKAGES.TXT

help() {
  echo usage: $SCRIPTNAME 'sPkgName'
}

fnPackageInfo() {
  type="$1" && shift
  case "$type" in
    "archive")
      echo "$1" | sed -n 's/\([^ ]*\)-\(\([0-9]\+\.\?[0-9.]\+[a-z]\?\)\|\([a-z]\{3\}[0-9]\+[^-]\+\)\).*\.\(tar.\|t\)\(xz\|gz\).*/\1|\2/p'
      ;;
    "dir")
      echo "$1" | sed -n 's/\([^ ]*\)-\(\([0-9]\+\.\?[0-9.]\+[a-z]\?\)\|\([a-z]\{3\}[0-9]\+[^-]\+\)\).*/\1|\2/p'
      ;;
    "iso_source")
      echo -e "$1" | sed -n 's/.*\.\/\([a-zA-Z]\+\)\/[^ ]*\/\([^ ]*\)-\([0-9]\+\.[0-9.]\+[.0-9]*[a-zA-Z]\?\)\([_-][0-9]*\)\?\.tar.\(xz\|gz\).*/[\1] \2 \3/p'
      ;;
    "iso_package")
      echo -e "$1" | sed -n 's/.*\.\/\([a-zA-Z]\+\)\/\([^ ]*\)-\([0-9]\+\.[0-9.]\+[.0-9]*[a-zA-Z]\?\)\([_-][0-9]*\)\?.*\.t\(xz\|gz\).*/[\1] \2 \3/p'
      ;;
    "remote")
      echo -e "$1" | sed -n 's/^PACKAGE NAME:[ ]*\([^ ]*\)-\([0-9._]\+[a-z]\?\)\-.*x86.*-.*LOCATION:[ ]*\.\/.*\/\([a-z]\).*/[\3] \1 \2/ip'
      ;;
  esac
}

sSearch() {
  search="$1" && shift
  if [ "$REPOSOURCE" != "current" ]; then
    # search source iso
    SOURCE=/mnt/iso/slackware-$REPOSOURCE-source/source
    if [ -d $SOURCE ]; then
      cd $SOURCE
      results="$(find . -iname "*$search*z" | grep "/.*$search.*/")"
      cd - 2>&1 > /dev/null
      if [ "x$results" == "x" ]; then
        echo "no package found" 1>&2
        return 1
      else
        fnPackageInfo "iso_source" "$results"
        return
      fi
    else
      echo "invalid source location: '$SOURCE'" 1>&2
    fi
    # search package iso
    SOURCEPKG=/mnt/iso/slackware$ARCHSUFFIX-$REPOSOURCE/slackware$ARCHSUFFIX
    if [ -d $SOURCEPKG ]; then
      cd $SOURCEPKG
      results="$(find . -iname "*$search*z")"
      cd - 2>&1 > /dev/null
      if [ "x$results" == "x" ]; then
        echo "no package found" 1>&2
        return 1
      else
        fnPackageInfo "iso_package" "$results"
        return
      fi
    else
      echo "invalid package location: '$SOURCEPKG'" 1>&2
    fi

  else
    # search remote

    #ensure list
    [ ! -f $PKGLISTLOCAL ] && slackpkg update
    [ ! $? ] && return 1

    results="$(sed -n '/^PACKAGE NAME:[ ]*.*'"$search"'.*/{N;s/\n\(.\)/|\1/;p}' $PKGLISTLOCAL)"
    fnPackageInfo "remote" "$results"
  fi
}

sDownload() {
  SEARCH="$1" && shift
  PATHTARGET=~/packages/
  DEBUG=0
  SOURCE=0
  if [ $# -gt 0 ]; then
    while [[ $# -gt 0 && "x`echo $1 | sed -n '/\(source\|src\)/p'`" != "x" ]]; do
      option="$1"
      case $option in
        "source"|"src") SOURCE=1 && shift ;;
        *) echo "unknown option: '$option'" && exit 1 ;;
      esac
    done
  fi

  [ $DEBUG -ge 1 ] && echo "source: '$SOURCE'"

  #search
  PKGS="$(sSearch "$SEARCH")"
  if [ ! $? -eq 0 ]; then return 1; fi
  IFS=$'\n'; PKGS=($PKGS); IFS="$IFSORG"

  for PKG in "${PKGS[@]}"; do
    PKG=(`echo $PKG`)
    type=${PKG[0]} && type=${type:1:$[${#type} - 2]}
    pkg=${PKG[1]} && [ "x$pkg" == "x" ] && return 1
    version=${PKG[2]}

    [ $DEBUG -ge 1 ] &&
      echo "found package: $pkg, version: $version, type: [$type]" 1>&2

    result=
    echo -n "[user] download package / source: '$pkg'? [y/n/c] "

    cancel=0
    download=1
    retry=1
    while [ $retry -eq 1 ]; do
      read -n 1 -s result
      case "$result" in
        "y" | "Y")
          echo $result
          retry=0
          ;;
        "n" | "N")
          echo $result
          download=0
          retry=0
          ;;
        "c" | "C")
          echo $result
          retry=0
          cancel=1
          ;;
      esac
    done
    [ $cancel -eq 1 ] && break

    if [ $download -eq 1 ]; then
      target="$pkg-$version"
      mkdir -p "$target"
      if [ "$REPOSOURCE" != "current" ]; then
        #local
        SOURCE=/mnt/iso/slackware-$REPOSOURCE-source/source
        SOURCEPKG=/mnt/iso/slackware$ARCHSUFFIX-$REPOSOURCE/slackware$ARCHSUFFIX
        cp -a $SOURCE/$type/$pkg/ "$target"
        cp $SOURCEPKG/$type/$pkg-$version*z "$target"
      else
        #remote
        if [ $DEBUG -eq 1 ]; then echo -e "PKG: \n$pkg"; fi
        PKGINFO=$(grep -B1 -A3 "^PACKAGE NAME:[ ]*$pkg-[0-9]\+.*" "$PKGLISTLOCAL")
        if [ $DEBUG -eq 1 ]; then echo -e "PKGINFO: \n$PKGINFO"; fi
        PKG=$(echo -e "$PKGINFO" | sed -n 's/^.*NAME:[ ]*\(.*\)/\1/p')
        PKGNAME=$(echo -e "$PKGINFO" | sed -n 's/^.*NAME:[ ]*\(.*\)-[0-9]\+.*\-.*x86.*-.*/\1/p')
        if [ $DEBUG -eq 1 ]; then echo -e "PKGNAME: \n$PKGNAME"; fi
        PKGLOCATION=$(echo -e "$PKGINFO" |   sed -n 's|^.*LOCATION:[ ]*.*/\(.*\).*$|\1|p')
        if [ $DEBUG -eq 1 ]; then echo -e "#downloading package data:"; fi
        #download

        ## pkg
        PKGLOCATION_BUILD="`sed -n /^[^#]/p /etc/slackpkg/mirrors`slackware$ARCHSUFFIX/$PKGLOCATION"
        PKGARCH="x86_64"
        if [ "x$ARCHSUFFIX" = "x64" ]; then
          PKGURL="${PKGLOCATION_BUILD}/${PKG}"
        else
          PKGLOCATION_BUILD="`echo "$PKGLOCATION_BUILD" | sed -n 's/slackware64/slackware/p'`"
          # test url to find correct x86 arch
          for arch in "i486" "i586" "i686"; do
            url="$PKGLOCATION_BUILD`echo "$PKG" | sed -n 's/'$PKGARCH'/'$arch'/p'`"
            [ "x`wget -S --spider $url 2>&1 | grep 'HTTP/1.1 200 OK'`" != "x" ] && PKGURL="$url" && break
          done
        fi
        if [ "x$PKGURL" != "x" ]; then
          wget --directory-prefix="$target" $WGETOPTS "$PKGURL"
        else
          echo "no package build found for arch '$ARCH'!"
        fi

        if [ $SOURCE -eq 1 ]; then
          ## source
          wget -P . -r --directory-prefix="$target" --no-host-directories --cut-dirs=5 --no-parent --level=2 --reject="index.html*" $WGETOPTS $URLSOURCE/$PKGLOCATION/$PKGNAME/
          res=$?
          [ -e "$target"/robots.txt ] && `rm "$target"/robots.txt`
          [ $res -ne 0 ] && echo "wget returned non-zero exit code ($res), aborting" && return $res
        fi
      fi
    fi
  done
}

slUpdate() {
  lReturn=0
  pkglist=/tmp/packages.current

  #refresh?
  refresh=0 && [ $# -gt 0 ] && [ "x$1" == "xforce" ] && refresh=1 && shift
  [ $refresh -eq 0 ] && [ $(date +%s) -gt $[ $(date -r $pkglist.all +%s) + $[7*24*60*60] ] ] && refresh=1
  if [ $refresh -eq 1 ]; then
    slackpkg update
    slackpkg search . > $pkglist.all
    echo "[user] $pkglist.all updated"
  else
    echo "[user] $pkglist.all already update to date (<1w old)"
  fi

  #filter blacklist
  echo "[user] filtering blacklisted packages"
  cp "$pkglist.all" "$pkglist"
  while read line; do
    match="$(echo "$line" | sed -n 's/^\([^#]*\).*$/\1/p')"
    [ "x$match" == "x" ] && continue
    sed -i '/^[^]]*\][- ]*'$match'/d' $pkglist
  done < /etc/slackpkg/blacklist

  return $lReturn
}

slList() {
  pkglist=/tmp/packages.current

  slUpdate

  option="$1"
  case "$option" in
    "new"|"uninstalled") grep -iP '^\[uninstalled\]' $pkglist | sort ;;
    "up"|"upg"|"update"|"updates"|"upgrade"|"upgrades") grep -iP '^\[\s*upgrade\s*\]' $pkglist | sort ;;
    *)
      # echo "[error] unsupported list option '$option'"
     grep -iP '$option' $pkglist | sort ;;
  esac

}

sbUpdate() {
  PKGLIST=/tmp/packages.slackbuilds
  PKGLISTREMOTE="$URLSLACKBUILDS$REPOSLACKBUILDS""/SLACKBUILDS.TXT"
  wget -P /tmp $WGETOPTS $PKGLISTREMOTE -O $PKGLIST.all
  if [ ! $? -eq 0 ]; then
    echo "[error] pulling package list from '$PKGLISTREMOTE'"
    return 1
  fi
  #process list
  #add search property - name-version per package
  sed -n "/^.*NAME:.*$/,/^.*VERSION:.*$/{/NAME:/{h;b};H;/VERSION:/{g;s|^.*NAME:\s*\(\S*\).*VERSION:\s\(\S*\)|SLACKBUILD PACKAGE: \1\-\2|p;x;p};b};p" $PKGLIST.all > $PKGLIST
  return $?
}

sbSearch() {
  PKGLIST=/tmp/packages.slackbuilds

  #ensure list
  if [ ! -f $PKGLIST ]; then sbUpdate; fi
  if [ ! $? -eq 0 ]; then return 1; fi

  sed -n "s|^SLACKBUILD PACKAGE: \(.*$1.*\)|\1|ip" "$PKGLIST"
}

sbDownload() {
  SEARCH="$1"
  DEBUG=1
  if [ $# -gt 1 ]; then
    if [ "x$2" == "no" ]; then DEBUG=0; fi
  fi
  PATHTARGET=~/packages/
  PKGLIST=/tmp/packages.slackbuilds

  #ensure list
  if [ ! -f $PKGLIST ]; then sbUpdate; fi
  if [ ! $? -eq 0 ]; then return 1; fi

  #search
  PKGS=($(sbSearch "$SEARCH"))
  if [ ! $? -eq 0 ]; then return 1; fi

  #error if none, continue if unique, list if multiple matches
  if [ ${#PKGS[@]} -eq 0 ]; then
    echo "[user] no package name containing '$SEARCH' found"
    return 0
  else
    SUFFIX=
    if [ ${#PKGS[@]} -gt 1 ]; then SUFFIX="s"; fi
    echo "found ${#PKGS[@]} slackbuild$SUFFIX package$SUFFIX matching search term '$SEARCH'"
    cancel=0
    for PKG in "${PKGS[@]}"; do
      download=1
      if [ $DEBUG -eq 1 ]; then
        result=
        echo -n "[user] download package: '$PKG'? [y/n/c] "
        retry=1
        while [ $retry -eq 1 ]; do
          read -n 1 -s result
          case "$result" in
            "y" | "Y")
              echo $result
              retry=0
              ;;
            "n" | "N")
              echo $result
              download=0
              retry=0
              ;;
            "c" | "C")
              echo $result
              retry=0
              cancel=1
              ;;
          esac
        done
      fi
      if [ $cancel -eq 1 ]; then break; fi
      if [ $download -eq 1 ]; then
        [ $DEBUG -ge 1 ] && echo -e "PKG: \n$PKG"
        PKGINFO=$(grep -A9 "^SLACKBUILD PACKAGE: $PKG\$" "$PKGLIST")
        [ $DEBUG -ge 1 ] && echo -e "PKGINFO: \n$PKGINFO"
        PKGNAME=$(echo -e "$PKGINFO" | sed -n 's|^.*NAME:\ \(.*\)$|\1|p')
        [ $DEBUG -ge 1 ] && echo -e "PKGNAME: \n$PKGNAME"
        PKGBUILD=$URLSLACKBUILDS$REPOSLACKBUILDS/$(echo -e "$PKGINFO" | sed -n 's|^.*LOCATION:\ \.\/\(.*\)\/.*$|\1|p')/$PKGNAME.tar.gz
        [ $DEBUG -ge 1 ] && echo -e "PKGBUILD: \n$PKGBUILD"
        PKGDATA=($(echo -e "$PKGINFO" | sed -n 's|^.*DOWNLOAD'$ARCH2':\ \(.*\)$|\1|p'))
        if [ ! "x$PKGDATA" == "x" ]; then
          PKGDATAMD5=($(echo -e "$PKGINFO" | sed -n 's|^.*MD5SUM'$ARCH2':\ \(.*\)$|\1|p'))
        else
          PKGDATA=($(echo -e "$PKGINFO" | sed -n 's|^.*DOWNLOAD:\ \(.*\)$|\1|p'))
          PKGDATAMD5=($(echo -e "$PKGINFO" | sed -n 's|^.*MD5SUM:\ \(.*\)$|\1|p'))
        fi
        [ $DEBUG -ge 1 ] && echo -e "PKGDATA: \n${PKGDATA[@]}"
        [ $DEBUG -ge 1 ] && echo -e "#downloading package data:"
        #download
        #IMPLEMENT:
        #checksum verification
        #checks on existing files
        wget -P . $WGETOPTS $PKGBUILD
        if [ $? -ne 0 ]; then return $?; fi
        for url in "${PKGDATA[@]}"; do
          wget -P . $WGETOPTS "$url"
          if [ $? -ne 0 ]; then return $?; fi
        done
      fi
    done
  fi
}

mlUpdate() {
  PKGLIST=/tmp/packages.multilib
  wget -P /tmp $WGETOPTS $URLMULTILIB"FILELIST.TXT" -O $PKGLIST.all
  sed -n 's|.*\ \.\/current\/\(.*t[gx]z$\)|\1|p' $PKGLIST.all > $PKGLIST
}

mlDownload() {
  SEARCH="$1"
  PATHTARGET=~/packages/
  PKGLIST=/tmp/packages.multilib
  if [ ! -f $PKGLIST ]; then
    echo "[error] no multilib package list at '$PKGLIST'"
    exit 1
  fi
  IFSORIG=$IFS
  packages=($(grep -P "$SEARCH" /tmp/packages.multilib))
  echo -n \#found ${#packages[@]}
  if [ ${#packages[@]} -eq 0 ]; then
    echo " packages"
  else
    if [ ${#packages[@]} -eq 1 ]; then
      echo " package"
    else
      echo " packages"
    fi
    for url in ${packages[@]}; do
      echo ${url##*/}
    done
    result=""
    echo -n "download listed packages to $PATHTARGET? [y/n]: "
    read -s -n 1 result
    if [[ "$result" == "Y" || "$result" == "y" ]]; then
      echo "$result"
      for url in ${packages[@]}; do
        echo "downloading package '${url##*/}'"
        set -x
        wget -P $PATHTARGET $WGETOPTS $URLMULTILIB/current/$url
        set +x
      done
    else
      echo ""
    fi
  fi
}

mlDownload2() {
  PATHTARGET=~/packages/
#  wget -P /tmp $WGETOPTS $URLMULTILIB/FILELIST.TXT
  sed -n 's|.*current\/\(.*t[gx]z$\)|\1|p' /tmp/FILELIST.TXT > /tmp/packages.multilib
  IFSORIG=$IFS
  IFS=$' ' #avoid stripping the \n newline
  packages=( $(grep -P "$1" /tmp/packages.multilib) )
  echo \#found ${#packages[@]} packages:
  echo ${packages[@]}
  IFS=$IFSORIG
  result=""
  echo -n download listed packages to $PATHTARGET? [y/n]
  read -s -n 1 result
  echo ""
  if [[ "$result" == "Y" || "$result" == "y" ]]; then
    IFS=$'\n' #now use the \n in the single array item to glob
    for url in ${packages[@]}; do
      echo downloading package \'${url##*/}\'
#      wget -P $PATHTARGET $WGETOPTS $URLMULTILIB/current/$url
    done
   IFS=$IFSORIG
 fi
}

prefixes() {
  FILE="$1"
  BUILDTYPE="$2"
  FORCE="$3"

  # processed flag
  flag="#[_slack] noprefix"
  match=`echo $flag | sed 's/\([][]\)/\\\\\1/g'`

  parsed=0
  if [ "x`grep "$match" $FILE`" != "x" ]; then
    parsed=1
    [ "x$FORCE" == "x" ] && return
  fi

  if [ "$BUILDTYPE" == "system" ]; then
    sed -ri '/[^\]usr/s|usr/local|usr|g' $SLACKBUILD
  elif [ "$BUILDTYPE" == "user" ]; then
    sed -ri '/[^\]usr/s|usr|usr/local|g' $SLACKBUILD
    sed -ri 's|(/local){2,}|/local|g' $SLACKBUILD
  fi

  [ $parsed -gt 0 ] &&
    sed -n -i '1{s/\(.*\)/\1\n'"$flag"'/mp;b};p' "$FILE"
}

slackbuild() {
  FORCE=0
  COMPAT=0
  BUILD=1
  INSTALL=1
  PKGNAME="$1" && shift
  if [ $# -gt 0 ]; then
    while [[ $# -gt 0 && "x`echo $1 | sed -n '/\(user\|system\|force\|compat\|convert\|noinstall\|nobuild\)/p'`" != "x" ]]; do
      option="$1"
      case $option in
        "user"|"system") BUILDTYPE=$1 && shift ;;
        "force") FORCE=1 && shift ;;
        "compat"|"convert") COMPAT=1 && shift ;;
        "nobuild") BUILD=0 && shift ;;
        "noinstall") INSTALL=0 && shift ;;
        *) echo "unknown option: '$option'" && exit 1 ;;
      esac
    done
  fi

  [ $DEBUG -ge 1 ] && echo "buildtype: '$BUILDTYPE', force: '$FORCE', compat: '$COMPAT'"

  if [ $BUILD -eq 1 ]; then
    if [ ! -f $PKGNAME.[Ss]lack[Bb]uild ]; then
      if [ -f $PKGNAME.tar.?z ]; then
        _extract ./$PKGNAME.tar.?z
        if [ ! -d ./$PKGNAME ]; then
          echo "tarbomb? no '$PKGNAME' dir found after extraction of '$PKGNAME.tar.?z'"
          exit 1
        fi
        cd ./"$PKGNAME"
      elif [ -d "$PKGNAME" ]; then
        cd ./"$PKGNAME"
      fi
    fi
    if [ ! -f $PKGNAME.[Ss]lack[Bb]uild ]; then
      echo "no slackbuild files found"
      exit 1
    fi
    mv ../$PKGNAME*.*[zm2] . 2>/dev/null
    #VERSION=${VERSION:-$(echo $PKGNAM-*.tar.?z* | rev | cut -f 3- -d . | cut -f 1 -d - | rev)}
    SLACKBUILD=$(ls ./$PKGNAME.?lack?uild)
    [ -h $SLACKBUILD ] && SLACKBUILD=$(readlink $SLACKBUILD)

    prefixes "$SLACKBUILD" "$BUILDTYPE" "$FORCE"

    chmod +x $SLACKBUILD
    echo "[user] building package: $PKGNAME"
    [ $DEBUG -lt 2 ] && ./$SLACKBUILD "$@" || bash -x ./$SLACKBUILD "$@"
    [ $? -ne 0 ] && exit 1
  fi

  COPY=1
  file=`ls /tmp/$PKGNAME-*t?z 2>/dev/null`
  [ ! -e "$file" ] &&
    file=`ls /tmp2/$PKGNAME-*t?z 2>/dev/null`
  [ ! -e "$file" ] &&
    file=`ls ./$PKGNAME-*t?z 2>/dev/null` && COPY=0
  if [ $COPY -eq 0 ]; then
    echo "using local package: '$file'"
  elif ! [[ ${#file} -gt 0 && -f $file ]]; then
    echo -e "[debug] no package build file found in 'tmp', build error?"
    exit 1
  else
    echo -e "\n[user] copying $file -> ./""${file##*/}\n"
    chksum=$(md5sum "$file" | cut -f1 -d" ")
    if [ "x$DEBUG" == "x1" ]; then
      if [ -f "${file##*/}" ]; then
        echo -e "existing target file: ./""${file##*/}"" md5: $(md5sum "$file" | cut -f1 -d" ") size: ""$(du -ah ""${file##*/}"" | cut -f1 -d$'\t')""\n"
        stat "${file##*/}"
  #      rm "${file##*/}"
      fi
      echo -e "\nsource file: ""$file"" md5: $chksum  size: ""$(du -ah ""$file"" | cut -f1 -d$'\t')""\n"
      stat "$file"
      echo ""
    fi
    l=1
    chksum2=""
    while [[ ! "x$chksum2" == "x$chksum" && $l -le 10 ]]; do
      echo -e -n "[$(date)]\ntarget file: ./""${file##*/}"" [$l] cp success: "
      cp $file ./
      if [ $? -ne 0 ]; then
        echo -e "no\n"
        echo "[debug] outright 'cp' failure"
        exit 1
      else
        chksum2=$(md5sum ./"${file##*/}" | cut -f1 -d' ')
        if [ "x$chksum" == "x$chksum2" ]; then
          echo -e "yes\n"
        else
          echo -e "no\n"
          echo -e "[user] md5: $chksum2 [vs $chksum]\nsize: ""$(du -ah ./""${file##*/}"" | cut -f1 -d$'\t')""\n"
        fi
        if [ "x$DEBUG" == "x1" ]; then
          stat "${file##*/}"
          echo ""
        fi
      fi
      l=$[$l+1]
    done
    if [ "x$chksum2" == "x$chksum" ]; then
      rm $file
    else
      echo "[debug] nfs failed to sync file copy in time"
      exit 1
    fi
  fi

  file="${file##*/}"
  if [ $COMPAT -eq 1 ]; then
    echo -e "[user] converting package: $PKGNAME\n"
    VERSION="`echo "$file" | sed -n 's/^'"$PKGNAME"'-\(.*\)-\([xi0-9]*86\|noarch\).*[tgbxz2]*$/\1/p'`"
    file="`echo $file | sed 's/x86_64/i686/'`"
    convertpkg-compat32 -i "$file"
    file_compat="`ls -1 $PKGNAME-compat*$VERSION*x86_64*t?z`"
    file="$file_compat"
  fi

  if [ $INSTALL -eq 1 ]; then
    echo -e "[user] installing package: $PKGNAME\n"
    upgradepkg --install-new --reinstall "$file"
    ldconfig
    echo -e "[user] linker cache:\n"
    ldconfig -p | grep -i $PKGNAME
    echo ""
  fi
}

build() {
  #simple build

  CONFIG=1
  BUILD=1
  INSTALL=1

  # args
  args=$@

  ## pkg name
  [[ ${#args[@]} -gt 0 && "x`echo "${args[0]}" | sed -n '/\(user\|system\|noconfig\|nobuild\|noinstall|\uninstall\|clean\|distclean\|vala-clean\)/p'`" == "x" ]] && pkg="${args[0]}" && args="${args[@]:1}"

  ## build
  if [ $# -gt 0 ]; then
    args2=()
    for arg in "${args[@]}"; do
      case "$arg" in
        "user"|"system") BUILDTYPE=$1 && shift ;;
        "noconfig") CONFIG=0 && shift ;;
        "nobuild") BUILD=0 && shift ;;
        "noinstall") INSTALL=0 && shift ;;
        *) args2=("${args2[@]}" "$arg") ;;
      esac
    done
    args="${args2[@]}"
  fi
  [ $DEBUG -ge 1 ] && echo "buildtype: '$BUILDTYPE', force: '$FORCE', compat: '$COMPAT'"

  ## build prep
  args2=()
  for arg in "${args[@]}"; do
    if [ "x`echo "$arg" | sed -n '/\(uninstall\|clean\|distclean\|vala-clean\)/p'`" != "x" ]; then
      make "$arg"
    else
      args2=("${args2[@]}" "$arg")
    fi
  done
  args="${args2[@]}"

  target=/usr/local
  [ "x$BUILDTYPE" == "xsystem" ] && target="/usr"

  arch2=$ARCH && [ "x${arch2:$[${#arch2}-2]}" == "x86" ] && arch2=x86
  [ "x${pkg:$[${#pkg}-${#arch2}-1]}" == "x-$arch2" ] && pkg=${pkg%-$arch2}
  [ ! -d $pkg-$arch2 ] && _extract $pkg.tar.* && mv $pkg $pkg-$arch2
  [ -d $pkg-$arch2 ] && cd $pkg-$arch2

  CFLAGS="-O0 -ggdb3 $CFLAGS"
  CXXFLAGS="-O0 -ggdb3 $CXXFLAGS"

  if [ $CONFIG -eq 1 ]; then
    [[ ! -f configure && -f autogen.sh ]] && ./autogen.sh
    echo CFLAGS=$CFLAGS CXXFLAGS=$CXXFLAGS LDFLAGS=$LDFLAGS \
      ./configure \
        --prefix=$target \
        --libdir=$target/lib`[ ${arch2#*_} == "64" ] && echo 64` \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --build=$ARCH-slackware-linux-gnu \
        "${args[@]}"
    CFLAGS=$CFLAGS CXXFLAGS=$CXXFLAGS LDFLAGS=$LDFLAGS \
      ./configure \
        --prefix=$target \
        --libdir=$target/lib`[ ${arch2#*_} == "64" ] && echo 64` \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --build=$ARCH-slackware-linux-gnu \
        "${args[@]}"

    ret=$? && [ $ret -ne 0 ] && exit $ret
  fi

  if [ $BUILD -eq 1 ]; then
    make -j 8 V=1
    ret=$? && [ $ret -ne 0 ] && exit $ret
  fi

  if [ $BUILD -eq 1 ]; then
    make install
    ret=$? && [ $ret -ne 0 ] && exit $ret
    ldconfig && ldconfig -p | grep -i ${pkg%%-*}
  fi
}

convert() {
  IFS=$'\n'; pkg=($(echo "$1" | sed 's/\([^-]*\)\-\([0-9.gitsvnba]*\)-\(x86_64\|i[4-6]86\|$\)-\([0-9]\|$\)\(_\?[a-zA-Z0-9]*\|$\)\(\.tar.*\|\.t[gx].*\|\)/\1\n\2\n\3\n\4/')); IFS=$IFSORG
  [ ${#pkg[@]} -ne 4 ] && echo "[error] cannot parse 'pkg-ver-arch-build' parts for '$1'" && exit 1
#  for s in "${pkg[@]}"; do echo $s; done
  convertpkg-compat32 -i "$1"
  ret=$? && [ $ret -ne 0 ] && exit $ret
  upgradepkg --reinstall --install-new ${pkg[0]}-compat32-${pkg[1]}-x86_64-${pkg[3]}*
  ret=$? && [ $ret -ne 0 ] && exit $ret
  ldconfig && ldconfig -p | grep ${pkg%%-*}
}

ftest() {
  target="$1" && shift
  case $target in
    "fnPackageInfo")
      if [ $# -eq 0 ]; then
        # archive
        type="archive"
        tests=("cyrus-sasl-2.1.26.tar.xz|cyrus-sasl|2.1.26"
               "giflib-5.1.1-x86_64-1.tgz|giflib|5.1.1")
        for s in ${tests[@]}; do
          in="$(echo "$s" | cut -d'|' -f1)"
          out="$(echo "$s" | cut -d'|' -f2-)"
          res=$($target "$type" "$in")
          echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        done
        # dir
        type="dir"
        tests=("callibre-git2019Feb01-x86_64|callibre|git2019Feb01")
        for s in ${tests[@]}; do
          in="$(echo "$s" | cut -d'|' -f1)"
          out="$(echo "$s" | cut -d'|' -f2-)"
          res=$($target "$type" "$in")
          echo "[$target | "$type" | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        done
        # iso source
        type="iso_source"
        in="./n/cyrus-sasl/cyrus-sasl-2.1.26-null-crypt.patch.gz ./n/cyrus-sasl/cyrus-sasl-2.1.26-size_t.patch.gz ./n/cyrus-sasl/cyrus-sasl-2.1.26.tar.xz"
        out="[n] cyrus-sasl 2.1.26"
        res=$($target "$type" "$in")
        echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        # iso package
        type="iso_package"
        in="./l/giflib-5.1.1-x86_64-1.txz"
        out="[l] giflib 5.1.1"
        res=$($target "$type" "$in")
        echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        # remote package
        type="remote"
        in="PACKAGE NAME:  ConsoleKit2-1.0.0-x86_64-3.txz\nPACKAGE LOCATION:  ./slackware64/l"
        out="[l] ConsoleKit2 1.0.0"
        res=$($target "$type" "$in")
        echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
      else
        type="$1" && shift
        in="$@"
        res=$($target "$type" "$in")
        echo "[$target | $type | ${in[@]}] out: '$res' | $([ "x$res" != "x" ] && echo "pass" || echo "fail")"
      fi
      ;;
    *)
      $target "$@"
      ;;
  esac
}

#args
[ ! $# -gt 0 ] && help && echo "[error] not enough args" && exit 1
[ "x$1" == "x-x" ] && DEBUG=1 && shift
[ ! $# -gt 0 ] && help && echo "[error] not enough args" && exit 1
option=$1 && shift
case "$(echo "$option" | awk '{print tolower($1)}')" in
  "slupdate"|"slu") slUpdate "$@" ;;
  "sllist"|"sll"|"list"|"l") slList "$@" ;;
  "sbdownload"|"sbd") sbDownload "$1" ;;
  "sbsearch"|"sbs") sbSearch "$1" ;;
  "sbupdate"|"sbu") sbUpdate "$1" ;;
  "mldownload"|"mld") mlDownload "$1" ;;
  "mlupdate"|"mlu") mlUpdate "$1" ;;
  "build"|"sb") build "$@" ;;
  "convert"|"cv") convert "$@" ;;
  "download"|"dl") sDownload "$@" ;;
  "search"|"srch") sSearch "$@" ;;
  "test") ftest "$@" ;;
  *) slackbuild "$option" "$@" ;;
esac

