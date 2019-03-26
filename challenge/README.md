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
        -ne, --no-edit  : don't invoke the editor by default
        -nss, --no-subshell  : don't drop into a subshell at the target
                               location
        -dec, --dump-edit-command  : echo editor command before exit
        -eec[=VAR], --export-edit-command[=VAR]
           : enables exporting of the derived editor command to the
             subshell var 'VAR' (default: challenge_)
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
## examples

assuming the downloaded problem files reside in the current directory e.g.:

```
> ls -1 *pdf *zip
array-manipulation-English.pdf
array-manipulation-testcases.zip
```
then:
```
> challenge_ hackerrank data.structures arrays hard array-manipulation
```
will result in the following directory / files structure
```
> ls -1R ./hackerrank/data.structures.-.arrays.-.hard.-.array.manipulation:

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
and with aid of the following hacks:
```
# ~/.shrc  <- sourced on login

if [ -n "$challenge_" ]; then
  set -m
  echo "# eval \$challenge"
  eval "$challenge_ </dev/tty >/dev/tty"
fi
```
then use of the `--no-edit` and `--export-edit-command` switches e.g.:
```
> challenge_ -ne -eec hackerrank data.structures arrays hard array-manipulation

```
will result in you being dropped into a subshell at the solution target with all solution files open in your designated editor

**note:** the solution files created are governed by the **`type_exts`** category map which matches on any part of the ***CATEGORYx*** terms specified in the call, e.g. ***data.structures*** -> ***cpp cs py js***. modify at will..

## dependencies
- unzip
- awk
- sed
