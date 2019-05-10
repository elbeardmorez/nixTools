# devel.sh

## description
miscellaneous development aids, wrappers and workflows

## usage
```
SYNTAX: devel_ [OPTION] [OPTION-ARG1 [OPTION-ARG2 .. ]]

with OPTION:

  -r, --refactor  : perform code refactoring

    SYNTAX: devel_ refactor [ARGS] TARGETS

    ARGS:
      -f, --filter FILTER  : regexp filter to limit files to work on
                             (default: '.*')
      -d, --depth MAXDEPTH  : limit files to within MAXDEPTH target
                              hierarchy level (default: 1)
      -m, --modify  : persist transforms
      -t, --transforms TRANSFORMS  : override default refactor
                                     transforms set. TRANSFORMS is a
                                     comma delimited list of supported
                                     transforms. the 'all' transform
                                     enables all implemented transforms
                                     (default: tabs,whitespace)
          TRANFORMS:
            tabs  : replace tab characters with 2 spaces
            whitespace  : remove trailing whitespace
            brackets  : inline leading control structure bracket
      -xi, --external-indent [PROFILE]  : use external gnu indent
                                          binary with PROFILE
                                          (default: standard*)
                                          (support: c)

      *note: see README.md for PROFILE types

    TARGETS  : target file(s) / dir(s) to work on

  -d, --debug  : call supported debugger

    SYNTAX: devel_ debug [-l LANGUAGE] [-d DEBUGGER]
                                [ARGS] [-- BIN_ARGS]

    -l, --language LANGUAGE  : specify target language (default: c)
    -d, --debugger  : override language specific default debugger

    ARGS:
      gdb:  NAME, [PID]
      node inspect:  SRC, [PORT]

      note: the above args are overriden by default by environment
            variables of the same name, and where not, are consumed
            in a position dependent manner

    support: c/c++|gdb, javascript|node inspect

  -cl, --changelog

    SYNTAX: devel_ changelog [ARGS]

  -c, --commits  : process diffs into fix/mod/hack repo structure

    SYNTAX: devel_ commits [ARGS]

    ARGS:
      [target]  : location of repository to extract/use patch set from
                  (default: '.')
      [prog]  : program name (default: target directory name)
      [vcs]  : version control type, git, svn, bzr, cvs (default: git)
      [count]  : number of patches to process (default: 1)
```

## examples

```
  $ devel_ debug zsh
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

## todo
- changelog, repo test or die

## dependencies
- procps-ng (pgrep, pidof)
- which (which)
- GNU indent (indent)
