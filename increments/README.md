# increments.sh

## description
given a search set and a target, find all files satisfying the search under the target location and return a match list to represent an incremental set

## examples
```
$ increments.sh -t test/source/ x.cpp
test/source/x.cpp
test/source/2/x.cpp file(s)
```

## todo
- ordering
- diff sets
