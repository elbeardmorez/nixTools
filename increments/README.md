# increments.sh

## description
given a search set and a target, find all files satisfying the search under the target location and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is then created

## examples
```
$ increments.sh -t test/source/ x.cpp
1531580747      21      test/source/x.cpp
1531580793      29      test/source/2/x.cpp
```

## todo
- search versions set
