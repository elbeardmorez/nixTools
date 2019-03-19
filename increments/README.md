# increments.sh

## description
given a search set and a target, find all files satisfying the search under/in the target and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is optionally created

## usage
```
SYNTAX: increments_ [OPTIONS] search [search2 ..]

  -t TARGETS, --target TARGETS  : pipe ('|') delimited list of search
where OPTIONS can be:
                                  targets (paths / tar archives)
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
  -nz, --no-zeros  : ignore 0 length files
  -bl LIST, --blacklist LIST  : pipe ('|') delimited list of strings
                                to rx match against search results
                                with any matched files removed from
                                the ultimate set
  -d, --diffs  : output incremental diffs of search matches
  -dd, --dump-diffs PATH  : write diffs to PATH (default: increments)
  -dm, --dump-matches PATH  : copy search matches to PATH
                              (default: matches)
  -ac, --auto-clean  : automatically clean dump targets (no prompt!)
  -dfp, --diff-format-paths  : format paths in any incremental diffs
                               generated to the standard
                               'a[/PATH]/FILE' 'b[/PATH]/FILE pair.
                               by default, PATH is stripped, and FILE
                               is set to the latter of the diff pair's
                               names. see environment variable below
                               for overrides
  -dfg, --diff-format-git  : add git mailinfo compatible headers to
                             diff files
  -dnp, --diff-numeric-prefixes  : prefix diff number to file name

environment variables:
  INCREMENTS_TARGET  : as detailed above
  INCREMENTS_SEARCH  : as detailed above
  INCREMENTS_VARIANTS  : as detailed above
  INCREMENTS_PRECEDENCE  : as detailed above
  DIFF_TARGET_BASE_PATH  : base path of file to be use in any
                           incremental diffs generated e.g.
                           'a/GIT_DIFF_BASE_PATH/FILE'
  DIFF_TARGET_FILE  : file name override for any incremental diffs
                      generated. e.g. 'b/DIFF_TARGET_FILE'
  GIT_DIFF_SUBJECT  : subject line for any incremental diffs generated
```

## examples
```
$ increments_ -t test/source/ x.cpp
[info] matched 2 files

path                 size                     date
test/source/2/x.cpp    29 2018Jul14 16:06:33 +0100
```

```
$ increments_ --target test/source/ --variants ./variants x.cpp
[info] matched 4 files

path                  size                     date
test/source/x.cpp~      14 2018Jul14 15:56:38 +0100
test/source/x.cpp       21 2018Jul14 16:05:47 +0100
test/source/2/x.cpp~    21 2018Jul14 16:06:17 +0100
test/source/2/x.cpp     29 2018Jul14 16:06:33 +0100
```

```
$ increments_ -t test/source/ --diffs x.cpp
...
[info] dumped 2 diffs to 'increments'

$ ls -1 increments
1531580747.diff
1531580793.diff
```

**example session**
```
$ cat ./variants
/\(.*\)/\1~/

$ nm=slack;\
  GIT_DIFF_SUBJECT="[mod] $nm.sh, "\
  DIFF_TARGET_BASE_PATH="$nm/"\
  DIFF_TARGET_FILE="$nm.sh"\
    increments_ -t "/backup/elbeardo.tar|\        : pipe delimited list of targets
                    $HOME/development/bash"\
                -v ./variants\                    : search variants file
                -nd\                              : remove duplicates
                --dump-diffs "diffs/$nm.sh"\      : push diff to dir
                --dump-matches "backup/$nm.sh"\   : push matches to dir
                -ac\                              : auto-clean dump dirs
                -dfg -dfp -dnp\                   : format diffs
                "/_$nm"                           : search term
[info] ignoring GNU tar 'not found in archive' 'errors'
[info] matched 83 files
[info] dumped 83 matches to 'backup/slack.sh'
[info] 5 unique files
[info] dumped 5 diffs to 'diffs/slack.sh'
[info] file list:
path                                                                       size                     date
/tmp/increments.sh.RSrW3lZZzJ/backup/monthly.10/development/bash/_slack~  12064 2013Sep24 07:45:37 +0100
/tmp/increments.sh.RSrW3lZZzJ/backup/monthly.10/development/bash/_slack   12054 2013Sep24 10:44:26 +0100
/tmp/increments.sh.RSrW3lZZzJ/backup/daily.10/development/bash/_slack~    12678 2014Jul17 10:26:12 +0100
/tmp/increments.sh.RSrW3lZZzJ/backup/daily.10/development/bash/_slack     12679 2014Jul17 10:27:37 +0100
~/development/bash/~sort/_slack~                                          21285 2019Feb07 18:05:52 +0000

$ ls -1 diffs/slack.sh
0001_1380005137.diff
0002_1380015866.diff
0003_1405589172.diff
0004_1405589257.diff
0005_1549562752.diff

$ sample=diffs/slack.sh/0001_1380005137.diff; head -n10 $sample && echo '...' && tail -n3 $sample
From fedcba10987654321012345678910abcdef Mon Sep 17 00:00:00 2001
From: Pete Beardmore <pete.beardmore@msn.com>
Date: Tue, 24 Sep 2013 07:45:37 +0100
Subject: [mod] slack.sh,

---

--- /dev/null   2019-02-07 19:04:32.633333967 +0000
+++ b/slack/slack.sh    2013-09-24 07:45:37.000000000 +0100
@@ -0,0 +1,407 @@
...
--
2.20.1
```

## dependencies

**required**  
- sed [GNU - '\t' usage]
- md5sum
- tee
- diff
- tar [GNU - '--wildcards' extension]
- date [GNU coreutils - '-d' and '@']

**optional**  
- git

## todo
