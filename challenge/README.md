# challenge.sh

## description
structures challenge files and opens a set of empty solution files in an editor

## usage
```
USAGE: challenge_ TYPE CATEGORY[ CATEGORY2 [CATEGORY3 ..]] NAME

where TYPE is:
  hackerrank  : requires challenge description pdf and testcases zip archive files
```
e.g.
```
> challenge_ hackerrank data.structures arrays hard array-manipulation
```

which given following files residing in the current directory:
```
array-manipulation-English.pdf
array-manipulation-testcases.zip
```

will result in the following directory / files hierarchy

```
./hackerrank/data.structures.-.arrays.-.hard.-.array.manipulation:
array.manipulation.cs
array.manipulation.js
array.manipulation.pdf
array.manipulation.py
array.manipulation.testcases.zip
input/
output/

./hackerrank/data.structures.-.arrays.-.hard.-.array.manipulation/input:
input00.txt
input14.txt

./hackerrank/data.structures.-.arrays.-.hard.-.array.manipulation/output:
output00.txt
output14.txt
```
solution files can be specified by modification of the category map

## dependencies
- unzip
