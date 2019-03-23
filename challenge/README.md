# challenge.sh

## description
coding challenge aid featuring structuring of challenge files and provision of a set of empty solution files ready for editing

## usage
```
SYNTAX: challenge_ [MODE [MODE_ARGS]]

where MODE can be:

  h, help  : this help information
  new [OPTIONS] TYPE CATEGORY[ CATEGORY2 [CATEGORY3 ..]] NAME
    :  create new challenge structure
    with:
      OPTIONS  :
        -nss, --no-subshell  : don't drop into a subshell at the target
                               location
      TYPE  : a supported challenge type
        hackerrank  : requires challenge description pdf and testcases
                      zip archive files
      CATEGORYx  : target directory name parts
      NAME  : solution name
  dump [LANGUAGES] TARGET  : search TARGET for files suffixed with
                             items in the delimited LANGUAGES list
                             (default: 'py|js|cs') and dump matches
                             to TARGET.LANGUAGE files
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
