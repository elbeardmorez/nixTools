# diff.sh

## description
diff related functionality

## usage
```
usage: _diff [TYPE [TYPE_ARGS]] [OPTION [OPTION_ARGS] ..] dir|file dir2|file2

where TYPE is:
  diff     : unified diff (default)
  dir      : force directory comparison
  changed  : list modified files

with supported OPTION(s):
  stripfiles FILE [FILE2 ..]     : ignore specified files
  striplines STRING [STRING2 ..] : ignore lines (regexp format)
  whitespace                     : ignore whitespace changes
```

## dependencies
- diff
