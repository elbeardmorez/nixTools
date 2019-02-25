# blog

## description
simple script for creating blog entry data in a basic key/value flat backend (file) format - cms / front-end agnostic

## usage
```
SYNTAX: blog_ [OPTION]

where OPTION is:
  new      : create a new entry
  publish  : (re)build and push temp data to 'publshed' target
  mod [SEARCH] : modify current unpublished item or a published item
                 via title search using matching SEARCH
```

## dependencies
- tr
- sed
- date [GNU coreutils - '-d' and '@']
