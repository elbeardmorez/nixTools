# file.sh

## description
'swiss-army knife' for all tasks file related.. well, a few tasks anyway. currently,  wrappers / routines for cleaning names (stripping leading / trailing chars, removing chars, changing case), removing duplicate lines, trimming lines, editing, dumping, duplicating and searching. target file(s) are set as either a directory of files, or those located (interactively where multiple are matched) through 'search.sh'

## usage
```
SYNTAX: file_ [OPTION [OPTION ARGS]] TARGET

where OPTION can be:

  -h|--help  : this help information
  -s|--strip [SIDE][COUNT]  : remove characters from target file name
    where SIDE  : either 'l' / 'r' denoting the side to remove char
                  from (default: r)
          COUNT  : the number of characters to remove from the given
                   side (default: 1)
  -u|--uniq  : remove duplicate lines from target file
  -e|--edit  : edit target file
  -d|--dump  : cat target file to stdout
  -f|--find SEARCH  : grep target file for SEARCH string
  -t|--trim [LINES] [END]  : trim target file
    where LINES  : number of lines to trim (default: 1)
          END  : either 'top' / 'bottom' denoting the end to trim from
                 (default: bottom)
  -r|--rename [OPTION] [TRANSFORMS]  : rename files using one or more
                                       supported transforms
    where OPTIONs:
      -f|--filter [FILTER]  : perl regular expression string for
                              filtering out (negative matching) target
                              files. a match against this string will
                              result in skipping of a target
                              (default: '')
    and TRANSFORMS is:  a delimited list of transform type
                        (default: lower|spaces|underscores|dashes)
      'lower'  : convert all alpha characters to lower case
      'upper'  : convert all alpha characters to upper case
      'spaces'  : compress and replace with periods ('.')
      'underscores' : compress and replace with periods ('.')
      'dashes' : compress and replace with periods ('.')
      'X=Y'  : custom string replacements
      '[X]=Y'  : custom character(s) replacements
  -dp|--dupe [DEST] [SUFFIX]  : duplicate TARGET to TARGET.orig, DEST,
                                or {TARGET}{DEST} dependent upon
                                optional arguments
    where DEST  : either a path or a suffix to copy the TARGET to
          SUFFIX  : either 0 or 1, determining what DEST is used as
                    (default: 0)
  -m|--move DEST  : move TARGET to DEST - a path, or an alias which
                    can be found in the rc file
                    ('~/.nixTools/file_')
  -xs|--search-args  : pass extra search arguments to 'search_'.
                       proceeding args (optionally up to a '--')
                       are considered search args

and TARGET is:  either a directory of files, or a (partial) file name
                  to be located via 'search.sh'
```
