# slack.sh

## description
script to aid in the building and installation of source and package based software on a Slackware system

this might be of use to someone who likes 'living on the edge' with a mix of major/current release packages, their own tweaked builds and non-packaged / aka 'raw source' installations

from a package management standpoint, wildcard search, pull and install quickly from local isos and remote repos

from a development standpoint, leverage 'slackbuilds.org' for source and build scripts where available. also attempt automated builds of some standard projects types from source

(re)building offers system/non-system ('user') flag to target the two standard target prefixes (`/usr` vs `/usr/local`)

## usage
```
usage: slack.sh [OPTION] [OPTION ARGS]

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
      np, no-package   : do not, where supported, download the slack
                         package
      ns, no-source   : do not, where supported. download source tarball
                        and build script

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
```

## dependencies

- Slackpkg (sl* options)
- BaSh like shell (various non-POSIX compliant features)
- tar
- Sed, Awk
- GNU coreutils (date)
