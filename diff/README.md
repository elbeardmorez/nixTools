# diff.sh

## description
diff related functionality

## usage
```
SYNTAX: diff_ [MODE] [OPTION [ARG] ..] dir|file dir2|file2

where MODE is:
  -d, --diff      : (default) unified diff output for targets
  -ch, --changed   : list modified common files in targets (dirs
                     only)
  -fl, --filelist  : comparison of file attributes in targets (dirs
                     only)

and OPTION can be:
  -sf, --strip-files FILE [FILE2 ..]      : ignore specified files
  -sl, --strip-lines STRING [STRING2 ..]  : ignore lines (regexp
                                            format)
  -nw, --no-whitespace  : ignore whitespace changes

note: advanced diff options can be passed to the diff binary
      directly using the '--' switch. any unrecognised options which
      follow will be treated as diff binary options
```

## dependencies
- diff
- gawk
- meld (or other diff viewer specified through DIFF_VIEWER environment variable)
