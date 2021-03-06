# search.sh

## description
ease location of your (regularly used) files. offers optionally interactive selection prompt for search match verification and for 'local' searches, target files are created where not found. thin wrapper around `find`, aimed for use with other onward scripts

## usage
```
SYNTAX 'search_ [OPTIONS] SEARCH

where 'OPTIONS' can be

  -h|--help  : this help information
  -i|--interactive [COUNT]  : enable verification prompt for each
                              match when more than COUNT (default: 0)
                              unique match(es) are found
  -t|--targets [TARGETS]  : override* search target path(s). TARGETS
                            can either be a path, or a file containing
                            paths, one path per line
                            (default: ~/.nixTools/search_)
  -ft|--file-types TYPES  : override the default search file types
                            (default: fl)

    TYPES  : non-delimited list of characters representing a file
             type, supporting:
      f  : file
      l  : symbolic link
      d  : directory

  -d|--depth DEPTH  : max depth of target hierarchies to search
  -r|--results TARGET  : file to dump search results to, one per line
  -v, --verbose  : output additional info

and 'SEARCH' is  : a (partial) file name to search for in the list of
                   search target paths*

*default: ~/documents

# state
rc: ~/.nixTools/search_ [found]
search target(s):
  ~/documents
```
