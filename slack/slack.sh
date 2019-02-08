#!/bin/sh
SCRIPTNAME="${0##*/}"
IFSORG="$IFS"

DEBUG=${DEBUG:-0}
ARCH2=${ARCH:-"$(uname -m)"} && [ ${ARCH2:$[${#ARCH2}-2]:2} == 64 ] && ARCHSUFFIX=64 && ARCH2=_x86_64
BUILDTYPE=user
WGETOPTS="--no-check-certificate"

REPO="${REPO:-slackware}"
declare -A REPOVERDEFAULTS
REPOVERDEFAULTS['slackware']='current'
REPOVERDEFAULTS['multilib']='current'
REPOVERDEFAULTS['slackbuilds']='14.2'
REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}}
declare -A REPOURL
REPOURL['slackware']='https://mirror.slackbuilds.org/slackware'
REPOURL['multilib']='http://slackware.com/~alien/multilib'
REPOURL['slackbuilds']='http://slackbuilds.org/slackbuilds'
PKGLIST='/tmp/_slack.packages'
PKGLISTMAXAGE=$[7*24*60*60]
SLACKPKGLIST=/var/lib/slackpkg/PACKAGES.TXT
SLACKPKGBLACKLIST=/etc/slackpkg/blacklist
SLACKPKGMIRRORS=/etc/slackpkg/mirrors
ISOPACKAGES=/mnt/iso/slackware$ARCHSUFFIX-$REPOVER/slackware$ARCHSUFFIX
ISOSOURCE=/mnt/iso/slackware-$REPOVER-source/source

help() {
  echo -e "
usage: $SCRIPTNAME [OPTION] [OPTION ARGS]\n
where OPTION is:

  # slack packages / sources list:
  u, update  : update lists of packages from all repositories
               (configured through Slackpkg) and their current state
               on the system

  s, search PKG  : wildcard search package 'PKG' locally (slackware
                   isos) or remotely (slackware repository) based on
                   'REPOVER'

  d, download PKG [ARG]  : pull packages matching 'PKG' from either
                           local or remote resources
    where [ARG] can be:
      src, source  : also download source tarball and build script

  l, list [ARG1 [ARG2]]  : list packages types of ARG1, or search
                           in list
    where [ARG1] can be:
      new, uninstalled      : list new/uninstalled packages
      up, update, upgrade   : list upgradable packages
      search [ARG2]         : (default) list packages matching ARG2

  # multilib packages:
  mlu, mlupdate        : update current multilib package list
  mls, mlsearch PKG    : wildcard search package list for package 'PKG'
  mld, mldownload PKG  : download packages matching 'PKG' from
                         the multilib repository

  # slackbuild sources:
  sbu, sbupdate        : update current slackbuilds.org package list
  sbs, sbsearch PKG    : wildcard search package list for package 'PKG'
  sbd, sbdownload PKG  : download packages matching 'PKG' from
                         the slackbuilds.org repository

  # builds
  bs, buildscript PKG [ARGS]  : build package PKG using build scripts
                                or in the standard slackbuilds.org
                                build script archives located in pwd
    where [ARGS] can be
      system     : ensure any instances of the standard '/usr/local'
                   prefix are set to '/usr'
                   [note: use escapes (e.g. '/\usr') to protect paths]
      user       : ensure any instances of the standard '/usr'
                   prefix are set to '/usr/local'
                   [note: use escapes (e.g. '/\usr') to protect paths]
      convert    : create an x86_64 compatibility package from built
                   package
      nobuild    : skip building of package
      noinstall  : skip installation of package

  bat, buildautotool [PKG-VER] [ARGS..]  : source only build and
                                           install for autotools
                                           projects
    where [ARGS] can be
      system     : target '/usr' prefix
      user       : target '/usr/local' prefix
      convert    : create an x86_64 compatibility package from built
                   package
      noconfig   : skip configuration of source
      nobuild    : skip building of source
      noinstall  : skip installation of source
      uninstall, clean,       : identified as 'make' targets which are
      dist-clean, vala-clean    executed prior to build
      *                       : all other args passed to make

  # packages
  cv, convert PKG  : find x86 package build in PWD and convert to
                     x86_64 compatibility package

environment variable switches:

  ARCH     : override current system architecture for builds
  REPO     : 'slackware' (default), sets the target version for
             package / source searching and downloading. overridden
             by suffixed flavours of the standard option names
             (e.g. 'sbdownload' implies REPO='slackbuilds')
  REPOVER  : 'current' (default), sets the target version for package
             / source searching and downloading
"
}

fnExtract() {
  archive="$1"
  target="$2"
  [ -f "./$archive" ] && archive="$(pwd)/$archive"
  [ ! -d "$target" ] && mkdir -p "$target"
  cd "$target"
  tar -xf "$archive"
  [ $(ls -1 | wc -l) == 1 ] && d=$(echo *) && mv "$d"/* . && rmdir "$d"
  cd - >/dev/null 2>&1
}

fnPackageInfo() {
  type="$1" && shift
  case "$type" in
    "string")
      echo "$1" | sed -n 's/\([^ ]*\)[|^-]\(\([0-9]\+\.\?[0-9.]\+[a-z]\?\)\|\([a-z]\{3\}[0-9]\+[^-]\+\)\)/\1|\2/p'
      ;;
    "archive")
      echo "$1" | sed -n 's/\([^ ]*\)-\(\([0-9]\+\.\?[0-9.]\+[a-z]\?\)\|\([a-z]\{3\}[0-9]\+[^-]\+\)\).*\.\(tar.\|t\)\(xz\|gz\).*/\1|\2/p'
      ;;
    "dir")
      echo "$1" | sed -n 's/\([^ ]*\)-\(\([0-9]\+\.\?[0-9.]\+[a-z]\?\)\|\([a-z]\{3\}[0-9]\+[^-]\+\)\).*/\1|\2/p'
      ;;
    "iso_source")
      echo -e "$1" | sed -n 's/.*\.\/\([a-zA-Z]\+\)\/[^ ]*\/\([^ ]*\)-\([0-9]\+\.[0-9.]\+[.0-9]*[a-zA-Z]\?\)\([_-][0-9]*\)\?\.tar.\(xz\|gz\|bz2\).*/[\1] \2 \3/p'
      ;;
    "iso_package")
      echo -e "$1" | sed -n 's/.*\.\/\([a-zA-Z]\+\)\/\([^ ]*\)-\([0-9]\+\.[0-9.]\+[.0-9]*[a-zA-Z]\?\)\([_-][0-9]*\)\?.*\.t\(xz\|gz\).*/[\1] \2 \3/p'
      ;;
    "remote")
      echo -e "$1" | sed -n 's/^PACKAGE NAME:[ ]*\([^ ]*\)-\([0-9._]\+[a-z]\?\)\-.*x86.*-.*LOCATION:[ ]*\.\/.*\/\([a-z]\).*/[\3] \1 \2/ip'
      ;;
  esac
}

fnRepoSwitch() {
  repover="$1"
  mirrors="${2:-$SLACKPKGMIRRORS}"
  current="$(sed -n '/^[ \t]*[^#]\+$/p' $mirrors)"
  [ "x$current" == "x" ] && echo "[error] no mirrors live in mirror list" && exit 1
  switched=0
  if [ "x$(echo "$current" | sed -n '/slackware\(64\)\?\-'$repover'/p')" == "x" ]; then
    sed -i '/^[ \t]*[^#]\+$/{s/slackware\(64\)\?\-[^/]\+/slackware\1-'$repover'/}' $mirrors
    current="$(sed -n '/^[ \t]*[^#]\+$/p' $mirrors)"
    switched=1
  fi
  echo "[user] $([ $switched -eq 1 ] && echo "switched to ")using slackpkg mirror '$current'" 1>&2
  return $switched
}

fnUpdate() {
  pkglist=${PKGLIST}.${REPO}-${REPOVER}

  case "$REPO" in
    "slackware")
      # switches
      refresh=0
      filter=0
      # refresh?
      [ $# -gt 0 ] && [ "x$1" == "xforce" ] && refresh=1 && shift
      [[ $refresh -eq 0 && ! -f $pkglist.all ]] && refresh=1
      [[ $(date +%s) -gt $[ $(date -r $pkglist.all +%s) + $PKGLISTMAXAGE ] ]] && refresh=1
      if [ $refresh -eq 1 ]; then
        fnRepoSwitch $REPOVER
        slackpkg update 1>&2
        [ ! $? ] && echo "[error] updating package list through Slackpkg" && return 1
        cp $SLACKPKGLIST $pkglist.raw
        slackpkg search . > $pkglist.all
        filter=1
        echo "[user] '$pkglist.all' updated" 1>&2
      else
        echo "[user] '$pkglist.all' less than 'PKGLISTMAXAGE [${PKGLISTMAXAGE}s]' old, not updating" 1>&2
      fi

      # filter blacklist?
      [[ $filter -eq 0 && ! -f $pkglist ]] && filter=1
      [[ $filter -eq 0 && $(date -r "$SLACKPKGBLACKLIST" +%s) -gt $(date -r $pkglist +%s) ]] && filter=1

      if [ $filter -eq 1 ]; then
        cp "$pkglist.all" "$pkglist"
        lc=$(cat $pkglist | wc -l)
        while read line; do
          match="$(echo "$line" | sed -n 's/^\([^#]*\).*$/\1/p')"
          [ "x$match" == "x" ] && continue
          sed -i '/.*'$match'-[^-]\+-[^-]\+-[^-]\+\( \|\t\|$\)/d' $pkglist
        done < $SLACKPKGBLACKLIST
        lc2=$(cat $pkglist | wc -l)
        echo "[user] filtered $(($lc-$lc2)) blacklisted package entries" 1>&2
      fi
      ;;

    "multilib")
      wget -P /tmp $WGETOPTS ${REPOURL['multilib']}/"FILELIST.TXT" -O $pkglist.all
      sed -n 's|.*\ \.\/'$REPOVER'\/\(.*t[gx]z$\)|\1|p' $pkglist.all > $pkglist
      ;;

    "slackbuilds")
      PKGLISTREMOTE="${REPOURL['slackbuilds']}/$REPOVER""/SLACKBUILDS.TXT"
      wget -P /tmp $WGETOPTS $PKGLISTREMOTE -O $pkglist.all
      [ ! $? ] && echo "[error] pulling package list from '$PKGLISTREMOTE'" && return 1
      #process list
      #add search property - name-version per package
      sed -n "/^.*NAME:.*$/,/^.*VERSION:.*$/{/NAME:/{h;b};H;/VERSION:/{g;s|^.*NAME:\s*\(\S*\).*VERSION:\s\(\S*\)|SLACKBUILD PACKAGE: \1\-\2|p;x;p};b};p" $pkglist.all > $pkglist
      ;;
  esac

  return $?
}

fnSearch() {
  pkglist=${PKGLIST}.${REPO}-${REPOVER}

  case "$REPO" in
    "slackware")
      search="$1" && shift
      if [ "$REPOVER" != "current" ]; then
        # search packages iso
        source="$ISOPACKAGES"
        if [ -d "$source" ]; then
          cd "$source"
          results="$(find . -iname "*$search*z")"
          cd - 2>&1 > /dev/null
          if [ "x$results" == "x" ]; then
            echo "[info] no package found" 1>&2 && return 1
          else
            fnPackageInfo "iso_package" "$results"
            return
          fi
        else
          echo "[error] invalid package location: '$source'" 1>&2
        fi
      else
        # search remote
        # ensure list or die
        fnUpdate
        [ ! $? ] && return 1

        results="$(sed -n '/^PACKAGE NAME:[ ]*.*'"$search"'.*/{N;s/\n\(.\)/|\1/;p}' $pkglist.raw)"
        fnPackageInfo "remote" "$results"
      fi
      ;;

    "multilib")
      # ensure list or die
      fnUpdate
      [ ! $? ] && return 1

      search="$1"
      grep -P "$search" $pkglist
      ;;

    "slackbuilds")
      # ensure list or die
      fnUpdate
      [ ! $? ] && return 1

      search="$1"
      sed -n 's/^SLACKBUILD PACKAGE: \(.*'"$search"'.*\)/\1/ip' $pkglist
      ;;
  esac

  return $?
}

fnDownload() {
  pkglist=${PKGLIST}.${REPO}-${REPOVER}

  case "$REPO" in
    "slackware")
      search="$1" && shift
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

      # search
      packages="$(fnSearch "$search")"
      [ ! $? ] && return 1

      IFS=$'\n'; packages=($packages); IFS="$IFSORG"
      for PKG in "${packages[@]}"; do
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
          if [ "$REPOVER" != "current" ]; then
            #local
            ## sources
            source="$ISOSOURCE"
            cp -a "$source"/$type/$pkg/ "$target"
            ## packages
            source="$ISOPACKAGES"
            cp -a "$source"/$type/$pkg-$version*z "$target"
          else
            #remote
            if [ $DEBUG -eq 1 ]; then echo -e "PKG: \n$pkg"; fi
            PKGINFO=$(grep -B1 -A3 "^PACKAGE NAME:[ ]*$pkg-[0-9]\+.*" "$pkglist.raw")
            if [ $DEBUG -eq 1 ]; then echo -e "PKGINFO: \n$PKGINFO"; fi
            PKG=$(echo -e "$PKGINFO" | sed -n 's/^.*NAME:[ ]*\(.*\)/\1/p')
            PKGNAME=$(echo -e "$PKGINFO" | sed -n 's/^.*NAME:[ ]*\(.*\)-[0-9]\+.*\-.*x86.*-.*/\1/p')
            if [ $DEBUG -eq 1 ]; then echo -e "PKGNAME: \n$PKGNAME"; fi
            PKGLOCATION=$(echo -e "$PKGINFO" |   sed -n 's|^.*LOCATION:[ ]*.*/\(.*\).*$|\1|p')
            if [ $DEBUG -eq 1 ]; then echo -e "#downloading package data:"; fi
            #download

            ## pkg
            PKGLOCATION_BUILD="$(sed -n '/^[ \t]*[^#]\+$/p' $SLACKPKGMIRRORS)slackware$ARCHSUFFIX/$PKGLOCATION"
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
              wget -P . -r --directory-prefix="$target" --no-host-directories --cut-dirs=5 --no-parent --level=2 --reject="index.html*" $WGETOPTS ${REPOURL['slackware']}/slackware$ARCHSUFFIX-$REPOVER/source/$PKGLOCATION/$PKGNAME/
              res=$?
              [ -e "$target"/robots.txt ] && `rm "$target"/robots.txt`
              [ $res -ne 0 ] && echo "wget returned non-zero exit code ($res), aborting" && return $res
            fi
          fi
        fi
      done
      ;;

    "multilib")
      search="$1" && shift
      PATHTARGET=~/packages/

      # search
      packages="$(fnSearch "$search")"
      [ ! $? ] && return 1

      IFS=$'\n'; packages=($packages); IFS="$IFSORG"

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
            wget -P $PATHTARGET $WGETOPTS ${REPOURL['multilib']}/current/$url
            set +x
          done
        else
          echo ""
        fi
      fi
      ;;

    "slackbuilds")
      search="$1"
      DEBUG=1
      if [ $# -gt 1 ]; then
        if [ "x$2" == "no" ]; then DEBUG=0; fi
      fi

      # search
      packages="$(fnSearch "$search")"
      [ ! $? ] && return 1

      IFS=$'\n'; packages=($packages); IFS="$IFSORG"

      # error if none, continue if unique, list if multiple matches
      if [ ${#packages[@]} -eq 0 ]; then
        echo "[user] no package name containing '$search' found"
        return 0
      else
        SUFFIX=
        if [ ${#packages[@]} -gt 1 ]; then SUFFIX="s"; fi
        echo "found ${#packages[@]} slackbuild$SUFFIX package$SUFFIX matching search term '$search'"
        cancel=0
        for PKG in "${packages[@]}"; do
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
            PKGINFO=$(grep -A9 "^SLACKBUILD PACKAGE: $PKG\$" "$pkglist")
            [ $DEBUG -ge 1 ] && echo -e "PKGINFO: \n$PKGINFO"
            PKGNAME=$(echo -e "$PKGINFO" | sed -n 's|^.*NAME:\ \(.*\)$|\1|p')
            [ $DEBUG -ge 1 ] && echo -e "PKGNAME: \n$PKGNAME"
            PKGBUILD=${REPOURL['slackbuilds']}/$REPOVER/$(echo -e "$PKGINFO" | sed -n 's|^.*LOCATION:\ \.\/\(.*\)\/.*$|\1|p')/$PKGNAME.tar.gz
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
      ;;
  esac
}

fnList() {

  #args
  [ $# -eq 0 ] && help && echo "[error] not enough args" && exit 1

  case "$REPO" in
    "slackware")
      option="search"
      [[ "x$(echo "$1" | sed -n '/[-]*\(new\|uninstalled\|up\|\upg\|upd\|update\|\updates\|upgrade\|upgrades\|search\)"/p')" != "x" || $# -gt 1 ]] && option="$1" && shift

      pkglist=/tmp/packages.current
      fnUpdate

      case "$option" in
        "new"|"uninstalled") grep -iP '^\[uninstalled\]' $pkglist | sort ;;
        "up"|"upg"|"upg"|"update"|"updates"|"upgrade"|"upgrades") grep -iP '^\[\s*upgrade\s*\]' $pkglist | sort ;;
        "search")
          [ $# -eq 0 ] && help && echo "[error] not enough args" && exit 1
          grep -iP "$1" $pkglist | sort
          ;;
        *)
          help && echo "[error] unsupported list option '$option'" && exit 1
          ;;
      esac
      ;;
    *)
      echo "[user] unsupported repo type '$REPO'" && exit 1
      ;;
  esac
}

fnPrefixes() {
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

fnBuild() {
  type="$1" && shift

  case $type in
    "script")

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
            fnExtract ./$PKGNAME.tar.?z "$PKGNAME"
            [ ! -d ./$PKGNAME ] &&
              echo "tarbomb? no '$PKGNAME' dir found after extraction of '$PKGNAME.tar.?z'" && exit 1
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

        fnPrefixes "$SLACKBUILD" "$BUILDTYPE" "$FORCE"

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
      ;;

    "autotool")
      CONFIG=1
      BUILD=1
      INSTALL=1

      ## package info
      s=""
      [[ $# -gt 0 && "x`echo "$1" | sed -n '/\(user\|system\|noconfig\|nobuild\|noinstall\)/p'`" == "x" ]] && s=$(fnPackageInfo "string" "$1")
      [ "x$s" != "x" ] && pkg="$(echo $s | cut -d'|' -f1)" && pkgver="$(echo $s | cut -d'|' -f2)" && shift
      [ "x$pkg" == "x" ] && s="$(fnPackageInfo "dir" $(basename $(pwd)))"
      [ "x$s" != "x" ] && pkg="$(echo $s | cut -d'|' -f1)" && pkgver="$(echo $s | cut -d'|' -f2)"
      [ "x$pkg" == "x" ] && help && echo "[error] cannot determine package details" && exit 1

      ## switches
      if [ $# -gt 0 ]; then
        declare -a args
        while [ $# -gt 0 ]; do
          arg="$1"
          case "$arg" in
            "user"|"system") BUILDTYPE="$arg" && shift ;;
            "noconfig") CONFIG=0 && shift ;;
            "nobuild") BUILD=0 && shift ;;
            "noinstall") INSTALL=0 && shift ;;
            *) args[${#args[@]}]="$arg" ;;
          esac
        done
      fi
      [ $DEBUG -ge 1 ] && echo "buildtype: '$BUILDTYPE', force: '$FORCE', compat: '$COMPAT'"

      ## build prep
      declare -a args2
      for arg in "${args[@]}"; do
        if [ "x`echo "$arg" | sed -n '/\(uninstall\|clean\|distclean\|vala-clean\)/p'`" != "x" ]; then
          make "$arg"
        else
          args2[${#args2}]="$arg"
        fi
      done
      args="${args2[@]}"

      target=/usr/local
      [ "x$BUILDTYPE" == "xsystem" ] && target="/usr"

      arch2=$ARCH && [ "x${arch2:$[${#arch2}-2]}" == "x86" ] && arch2=x86

      ## build source
      if [[ ! -f "./configure" && ! -f "./autogen.sh" ]]; then
        if [ -d "$pkg-$pkgver-$arch2" ]; then
          cd "$pkg-$pkgver-$arch2" >/dev/null 2>&1
        elif [ -d "src-$arch2" ]; then
          cd "src-$arch2" >/dev/null 2>&1
        else
          archive="$(echo $pkg-$pkgver*.t*z)" # glob expand
          if [ -f "$archive" ]; then
            dir="$pkg-$pkgver-$arch2"
            fnExtract "$archive" "$dir"
            [ -d "$dir" ] && cd "$dir" >/dev/null 2>&1
          fi
        fi
        [[ ! -f "./configure" && ! -f "./autogen.sh" ]] &&
          echo "[error] could not locate or extract usable source" && exit 1
      fi

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

      ;;
  esac
}

fnConvert() {
  IFS=$'\n'; pkg=($(echo "$1" | sed 's/\([^-]*\)\-\([0-9.gitsvnba]*\)-\(x86_64\|i[4-6]86\|$\)-\([0-9]\|$\)\(_\?[a-zA-Z0-9]*\|$\)\(\.tar.*\|\.t[gx].*\|\)/\1\n\2\n\3\n\4/')); IFS=$IFSORG
  [ ${#pkg[@]} -ne 4 ] && echo "[error] cannot parse 'pkg-ver-arch-build' parts for '$1'" && exit 1
#  for s in "${pkg[@]}"; do echo $s; done
  convertpkg-compat32 -i "$1"
  ret=$? && [ $ret -ne 0 ] && exit $ret
  upgradepkg --reinstall --install-new ${pkg[0]}-compat32-${pkg[1]}-x86_64-${pkg[3]}*
  ret=$? && [ $ret -ne 0 ] && exit $ret
  ldconfig && ldconfig -p | grep ${pkg%%-*}
}

fnTest() {
  target="$1" && shift
  case $target in
    "fnPackageInfo")
      if [ $# -eq 0 ]; then
        # string
        type="string"
        tests=("openssl-1.0.1e openssl|1.0.1e"
               "xorg-git2018Jun20 xorg|git2018Jun20"
               "optipng|0.7.7 optipng|0.7.7")
        for s in "${tests[@]}"; do
          in="$(echo "$s" | cut -d' ' -f1)"
          out="$(echo "$s" | cut -d' ' -f2)"
          res=$($target "$type" "$in")
          echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        done
        # archive
        type="archive"
        tests=("cyrus-sasl-2.1.26.tar.xz cyrus-sasl|2.1.26"
               "giflib-5.1.1-x86_64-1.tgz giflib|5.1.1")
        for s in "${tests[@]}"; do
          in="$(echo "$s" | cut -d' ' -f1)"
          out="$(echo "$s" | cut -d' ' -f2)"
          res=$($target "$type" "$in")
          echo "[$target | $type | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        done
        # dir
        type="dir"
        tests=("callibre-git2019Feb01-x86_64 callibre|git2019Feb01")
        for s in "${tests[@]}"; do
          in="$(echo "$s" | cut -d' ' -f1)"
          out="$(echo "$s" | cut -d' ' -f2)"
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
    "fnExtract")
      in=($@)
      $target ${in[@]}
      res=$([[ $? -eq 0 && -d "${in[1]}" ]] && echo $(ls -1 ${in[1]} | wc -l) || echo 0)
      echo "[$target | ${in[@]}] extracted count: '$res' | $([ $res -gt 0 ] && echo "pass" || echo "fail")"
      ;;
    "fnRepoSwitch")
      if [ $# -eq 0 ]; then
        f="$(tempfile)"
        echo '
#note
#http://ftp.gwdg.de/pub/linux/slackware/slackware64-14.1/
#ftp://ftp.gwdg.de/pub/linux/slackware/slackware64-14.2/
  http://ftp.gwdg.de/pub/linux/slackware/slackware64-current/
#
' > "$f"
        tests=("current 0"
               "14.1 1"
               "current 1")
        for s in "${tests[@]}"; do
          in="$(echo "$s" | cut -d' ' -f1)"
          out="$(echo "$s" | cut -d' ' -f2)"
          $($target "$in" "$f")
          res=$?
          echo "[$target | $in] out: '$res' | $([ "x$res" == "x$out" ] && echo "pass" || echo "fail")"
        done
        rm "$f"
      else
        [ $# -ne 2 ] && echo "[error] $target tests require 2 args"
        in=($@)
        before="$(sed -n '/^[ \t]*[^#]\+$/p' "${in[1]}")"
        $target ${in[@]}
        res=$?
        after="$(sed -n '/^[ \t]*[^#]\+$/p'  "${in[1]}")"
        echo -e "[$target | ${in[@]}] $([[ ($res -eq 0 && "x$before" == "x$after") ||
                                           ($res -eq 1 && "x$before" != "x$after") ]] &&
                                         echo "pass" || echo "fail")\nbefore: '$before'\nafter : '$after'"
      fi
      ;;
    *)
      $target "$@"
      ;;
  esac
}

option="buildscript"

#args
[ $# -eq 0 ] && help && echo "[error] not enough args" && exit 1

s="$(echo "$1" | awk '{s=tolower($0); gsub(/^[-]*/, "", s); print s}')"
[ "x$(echo "$s" | sed -n '/^\('\
'update\|u\|'\
'search\|s\|'\
'download\|d\|'\
'list\|l\|'\
'mlupdate\|mlu\|'\
'mlsearch\|mls\|'\
'mldownload\|mld\|'\
'sbupdate\|sbu\|'\
'sbsearch\|sbs\|'\
'sbdownload\|sbd\|'\
'buildscript\|bs\|'\
'buildautotool\|bat\|'\
'build\|bd\|'\
'convert\|cv\|'\
'test\|'\
'help\|h'\
'\)$/p')" != "x" ] && option="$s" && shift

case "$option" in
  "update"|"u") fnUpdate "force" ;;
  "mlupdate"|"mlu") REPO=multilib REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnUpdate "$@" ;;
  "sbupdate"|"sbu") REPO=slackbuilds REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnUpdate "$@" ;;
  "search"|"s") fnSearch "$@" ;;
  "mlsearch"|"mls") REPO=multilib REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnSearch "$@" ;;
  "sbsearch"|"sbs") REPO=slackbuilds REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnSearch "$@" ;;
  "download"|"d") fnDownload "$@" ;;
  "mldownload"|"mld") REPO=multilib REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnDownload "$@" ;;
  "sbdownload"|"sbd") REPO=slackbuilds REPOVER=${REPOVER:-${REPOVERDEFAULTS[$REPO]}} fnDownload "$@" ;;
  "list"|"l") fnList "$@" ;;
  "buildscript"|"bs") fnBuild 'script' "$@" ;;
  "buildautotool"|"bat") fnBuild 'autotools' "$@" ;;
  "convert"|"cv") fnConvert "$@" ;;
  "test") fnTest "$@" ;;
  "help"|"h") help ;;
esac

