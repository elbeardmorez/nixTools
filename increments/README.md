# increments.sh

## description
given a search set and a target, find all files satisfying the search under/in the target and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is optionally created

## usage
```
SYNTAX: increments_ [OPTIONS] search [search2 ..]

where OPTIONS can be:
  -t TARGET, --target TARGET:  search TARGET (path / archive)
  -v VARIANTS, --variants VARIANTS  : consider search variants given
                                      by application of (sed) regexp
                                      transformations in VARIANTS file
  -pp PATHS, --path-precedence PATHS : pipe ('|') delimited list of
                                       partial paths for matching on
                                       search results in order to
                                       override the default order of
                                       the ultimate set when desired
  -nd, --no-duplicates  : use only first instance of any duplicate
                          files matched
  -d, --diffs  : output incremental diffs of search matches
  -dd, --dump-diffs PATH  : write diffs to PATH (default: increments)
  -dm, --dump-matches PATH  : copy search matches to PATH
                              (default: matches)
  -ac, --auto-clean  : automatically clean dump targets (no prompt!)
  -dfg, --diff-format-git  : add git mailinfo compatible headers to
                             diff files

environment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
```

## examples
```
$ increments.sh -t test/source/ x.cpp
[info] matched 2 files

path                 size                     date
test/source/2/x.cpp    29 2018Jul14 16:06:33 +0100
```

```
$ ./increments.sh --target test/source/ --variants ./variants x.cpp
[info] matched 4 files

path                  size                     date
test/source/x.cpp~      14 2018Jul14 15:56:38 +0100
test/source/x.cpp       21 2018Jul14 16:05:47 +0100
test/source/2/x.cpp~    21 2018Jul14 16:06:17 +0100
test/source/2/x.cpp     29 2018Jul14 16:06:33 +0100
```

```
$ increments.sh -t test/source/ --diffs x.cpp
...
[info] dumped 2 diffs to 'increments'

$ ls -1 increments
1531580747.diff
1531580793.diff
```

## dependencies

**required**  
- sed
- md5sum
- tee
- diff
- tar [GNU - '--wildcards' extension]
- date [GNU coreutils - '-d' and '@']

**optional**  
- git

## todo
