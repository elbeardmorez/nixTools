# search.sh

## description
ease location of your (regularly used) files. offers optionally interactive selection prompt for search match verification and for 'local' searches, target files are created where not found. thin wrapper around `find`, aimed for use with other onward scripts

## usage
```
SYNTAX 'search_ [OPTIONS] SEARCH

where 'OPTIONS' can be

  -h, --help  : this help information
  -i, --interactive  : enable verification prompt for each match
                       (default: off / auto-accept)
  -t TARGET, --target TARGETS  : override path to file containing
                                 search targets, one per line
                                 (default: ~/.search)
  -r TARGET, --results TARGET  : file to dump search results to, one
                                 per line

and 'SEARCH' is  : a (partial) file name to search for in the list of
                     predefined search paths*

*predefined paths are currently: 
~/documents
```
