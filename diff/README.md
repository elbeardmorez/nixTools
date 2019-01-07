# diff.sh

## description
diff related functionality

## usage
```
SYNTAX: diff_ [MODE] [OPTION [ARG] ..] dir|file dir2|file2

where MODE is:
  diff      : (default) unified diff output for targets
  changed   : list modified common files in targets (dirs only)
  filelist  : comparison of file attributes in targets (dirs only)

and OPTION can be:
  stripfiles FILE [FILE2 ..]      : ignore specified files
  striplines STRING [STRING2 ..]  : ignore lines (regexp format)
  whitespace  : ignore whitespace changes
```

## dependencies
- diff
- meld (or other diff viewer specified through DIFF_VIEWER environment variable)
