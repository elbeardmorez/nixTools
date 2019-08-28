# devel.sh

## description
miscellaneous development aids, wrappers and workflows

## usage
```
SYNTAX: devel_ [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]

with OPTION:

  -r|--refactor  : perform code refactoring

    SYNTAX: devel_ refactor [ARGS] TARGETS

    ARGS:
      -f|--filter FILTER  : regexp filter to limit files to work on
                            (default: '.*')
      -d|--depth MAXDEPTH  : limit files to within MAXDEPTH target
                             hierarchy level (default: 1)
      -m|--modify  : persist transforms
      -t|--transforms TRANSFORMS  : override default refactor
                                    transforms set. TRANSFORMS is a
                                    comma delimited list of supported
                                    transforms. the 'all' transform
                                    enables all implemented transforms
                                    (default: tabs,whitespace)

          TRANFORMS:
            tabs  : replace tab characters with 2 spaces
            whitespace  : remove trailing whitespace
            braces  : inline leading control structure braces

      -xi|--external-indent [PROFILE]  : use external gnu indent
                                         binary with PROFILE
                                         (default: standard*)
                                         (support: c)

      *note: see README.md for PROFILE types

    TARGETS  : target file(s) / dir(s) to work on

  -d|--debug  : call supported debugger

    SYNTAX: devel_ debug [-l LANGUAGE] [-d DEBUGGER]
                                [ARGS] [-- BIN_ARGS]

    -l|--language LANGUAGE  : specify target language (default: c)
    -d|--debugger  : override language specific default debugger

    ARGS:
      gdb:  NAME, [PID]
      node inspect:  SRC, [PORT]

      note: the above args are overriden by default by environment
            variables of the same name, and where not, are consumed
            in a position dependent manner

    support: c/c++|gdb, javascript|node inspect

  -cl|--changelog

    SYNTAX: devel_ changelog [ARGS] [TARGET]

    ARGS:
      -as|--anchor-start NUMBER  : start processing entries at line
                                   NUMBER, allowing for headers etc.
      -p|--profile NAME  : use profile temple NAME

        NAME:
          default:  %date version %id\n - %description (%author)
          update:  [1] \n##### %date\nrelease: %tag version: 
                   [>=1]- %description ([%author](%email))

      -f|--file FILE  : overwrite changelog file name
                        (default: 'CHANGELOG.md')
      -rxid|--rx-id REGEXP  : override (sed) regular expression used
                              to extract ids and thus delimit entries
                              (default: 'version \([^ ]*\)')
      -ae|--anchor-entry NUMBER  : override each entry's anchor line
                                   (line containing %id)
                                   (default: '1')

    TARGET:  location of repository to query for changes

  -c|--commits  : process diffs into fix/mod/hack repo structure

    SYNTAX: devel_ commits [OPTIONS] [SOURCE] TARGET

    with OPTIONS in:
      -st|--source-type [=TYPE]  : set source type

        with TYPE:
          vcs  : a version control repository
          dir  : a directory of patch files
          patch  : a single patch file
          auto  : automatically determined based on the above order
                  of precedence (default)

      -l|--limit [=LIMIT]  : limit number of patches to process to
                             LIMIT (default: 1)
      -f|--filter [=]FILTER  : only use commits matching the (regex)
                               expression FILTER. repeated filter args
                               are supported
      -rm|--repo-map [=CATEGORY]  : push diffs to sub-directory based
                                    upon the comma delimited CATEGORY
                                    list, with each item corresponding
                                    to a tier in the hierarchy
                                    (default: target directory name)
      -mrm|--multi-repo-map [=REPOS]  :
        map diffs to repositories selected from the comma delimited
        REPOS list
        (default: fix,mod,hack)
      -vcs|--version-control-system [=][SOURCE|]TARGET  :
        pipe-delimited override of default version control system
        types. supports source: git, subversion, bazaar | target: git
        (default: git)
      -d|--dump  : dump patch set only
      -o|order [=]TYPE  : process patchset in a specific order, which
                          in turn governs target output / commit order

        with TYPE:
          date  : patchset is processed in date order
          default  : patchset is processed in source order

      -im|--interactive-match  : interactively match when target diff
                                 name clashes are unresolvable
                                 (default: assumes 'new')
      -rn|--readme-name [=]NAME  : override default readme file name
                                   (default: README.md)
      -rs|--readme-status [=STATUS]  : append a commit status string
                                       to the readme entry
                                       (default: pending)
      -nr|--no-readme  : don't update target readme(s)
      -ac|--auto-commit [=MODE]  : attempt to commit to target repo(s)
                                   non-interactively

        with MODE:
          auto  : commit set unconditionally (default)
          verify  : require user verification prior to execution

    SOURCE  : location of repository to extract/use patch set from
              (default: '.')

    TARGET  : location of repository / directory to push diffs to

  -p|--port  : apply a set of tranforms to a source file

    SYNTAX: devel_ port [OPTIONS] TARGET

    with OPTIONS in:
      -x|--transforms FILE  : override location of file containing
                              transforms
                              (default: ~/.nixTools/devel_*)
      -xs|--transforms-source TYPE  : apply source transforms of TYPE
                                      (default: target file suffix)
      -xt|--transforms-target TYPE  : apply target transforms of TYPE
                                      (default: target file suffix)
      -xd|--transforms-debug LINE  : trace transforms at LINE(S)
                                     in a comma-delimited list
      -l|--lines RANGE  : limit replacements to lines specified by a
                          delimited RANGE
      -d|--diffs  : show diffs pre-transform
      -o|--overwrite  : persist changes to target
      -v|--verify  : interactive application of transforms
      -ie|--ignore-errors  : continue processing on error

    * transform format:

    FROM|TO [FROM2|TO2 ..]
    TRANSFORM

    where:

      FROM  : source language type
      TO  : target language type
      TRANSFORM  : valid sed expression
```

## examples

### debug
```sh
  $ devel_ debug zsh
```
```
   [1]   637 | -zsh
   [2]  1056 | -/bin/zsh
   [3]  2106 | -/bin/zsh
  ...

  ...
  [14] 28636 | -zsh
  [15] 30023 | -/bin/zsh
  [16] 30694 | -zsh
  select item # or e(x)it [1-16|x]: 15
  [user] debug: gdb zsh --pid=30023 ? [y/n]: y
```

### refactor
```sh
  $ head -n 20 usbreset.c
```
```
  #include <stdio.h>
  #include <unistd.h>
  #include <fcntl.h>  
  #include <errno.h> 
  #include <sys/ioctl.h>    
  #include <linux/usbdevice_fs.h>
  
  int main(int argc, char **argv)
  {
  	const char *filename;
  	int fd;
  	int rc;
  
  	if (argc != 2) {
  		fprintf(stderr, "Usage: usbreset device-filename\n");
  		return 1;
  	}
  	filename = argv[1];
  
```
```sh
  $ devel_ -r -t all usbreset.c
```
```
  ---------------------------------------------------------------------------
  > searching for 'new line characters preceding braces' in file 'usbreset.c'
  ---------------------------------------------------------------------------
  int main(int argc, char **argv)\n
  {

  ----------------------------------------------------------
  > searching for 'trailing whitespace' in file 'usbreset.c'
  ----------------------------------------------------------
  #include <fcntl.h>··
  #include <errno.h>·
  #include <sys/ioctl.h>····

  -----------------------------------------------------
  > searching for 'tab characters' in file 'usbreset.c'
  -----------------------------------------------------
  [ ]const char *filename;
  [ ]int fd;
  [ ]int rc;
  [ ]if (argc != 2) {
  [ ][ ]fprintf(stderr, "Usage: usbreset device-filename\n");
  [ ][ ]return 1;
```

## dependencies
- procps-ng (pgrep, pidof)
- which (which)
- GNU coreutils (head, tail, tac)
- GNU indent (indent)
- diff
