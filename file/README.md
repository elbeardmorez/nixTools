# file.sh

## description
'swiss-army knife' for all tasks file related.. well, a few tasks anyway. currently,  wrappers / routines for cleaning names (stripping leading / trailing chars, removing chars, changing case), removing duplicate lines, trimming lines, editing, dumping, duplicating and searching. target file(s) are set as either a directory of files, or those located (interactively where multiple are matched) through 'search.sh'

## usage
```
SYNTAX: file_ [OPTION [OPTION ARGS]] TARGET

where OPTION can be:

  -h, --help  : this help information
  -s [SIDECOUNT], --strip [SIDECOUNT]  : remove characters from target
                                         file name
    where SIDE  : either 'l' / 'r' denoting the side to remove char
                  from (default: r)
          COUNT  : the number of characters to remove from the given
                   side (default: 1)
  -u, --uniq  : remove duplicate lines from target file
  -e, --edit  : edit target file
  -d, --dump  : cat target file to stdout
  -f SEARCH, --find SEARCH  : grep target file for SEARCH string
  -t [LINES] [END], --trim [LINES] [END]  : trim target file
    where LINES  : number of lines to trim (default: 1)
          END  : either 'top' / 'bottom' denoting the end to trim from
                 (default: bottom)
  -r [FILTER] [TRANSFORMS], --rename [FILTER] [TRANSFORMS]
    : rename files using one or more supported transforms
    where FILTER  : string to match against target files. no match will
                    result in skipping
          TRANSFORMS  : delimited list comprising:
            'lower'  : convert all alpha characters to lower case
            'upper'  : convert all alpha characters to upper case
            'spaces'  : compress and replace with periods ('.')
            'underscores' : compress and replace with periods ('.')
            'dashes' : compress and replace with periods ('.')
            (default: lower|spaces|underscores|dashes)
  -dp [DEST] [SUFFIX], --dupe [DEST] [SUFFIX]
    : duplicate TARGET to TARGET.orig, DEST, or {TARGET}{DEST}
      dependent upon optional arguments
    where DEST  : either a path or a suffix to copy the TARGET to
          SUFFIX  : either 0 or 1, determining what DEST is used as
                    (default: 0)

and TARGET is:  either a directory of files, or a (partial) file name
                to be located via 'search.sh'
```
