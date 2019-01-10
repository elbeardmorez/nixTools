# increments.sh

## description
given a search set and a target, find all files satisfying the search under the target location and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is optionally created

## examples
```
$ increments.sh -t test/source/ x.cpp
[info] matched 2 files

path                 size                     date
test/source/x.cpp      21 2018Jul14 16:05:47 +0100
test/source/2/x.cpp    29 2018Jul14 16:06:33 +0100
```

```
$ increments.sh diffs -t test/source/ x.cpp
[info] dumped 2 diffs to 'increments'

$ ls -1 increments
1531580747.diff
1531580793.diff
```

## todo
- search versions set
