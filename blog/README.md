# blog

## description
simple script for creating or modifying blog entry data stored as a basic key/value flat backend (file) format - cms / front-end agnostic. target blog stores can be listed directly, else via a menu system for displaying, selecting, and performing operations

## usage
```
SYNTAX: blog_ [OPTIONS] [MODE [MODE_ARGS]]

where OPTIONS can be:

  -h, --help  : this help information
  -rc FILE, --resource-configuration FILE
    : use settings file FILE (default: ~/nixTools/blog_

and with MODE as:
  new  : creates a new blog entry
  publish  : (re)build and push temp data to 'publshed' target
  mod [SEARCH]  : modify current unpublished item or a published item
                  via title search on SEARCH
  list  : list published entries
  menu  : switch views interactively
```

## dependencies
- tr
- sed
- date [GNU coreutils - '-d' and '@']
- awk
