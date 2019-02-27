# blog

## description
simple script for creating blog entry data in a basic key/value flat backend (file) format - cms / front-end agnostic

## usage
```
SYNTAX: blog_ [OPTION [OPTIONARGS]]

where OPTION can be:

  h, help  : this help information
  new  : creates a new blog entry
  publish  : (re)build and push temp data to 'publshed' target
  mod [SEARCH]  : modify current unpublished item or a published item
                  via title search on SEARCH
```

## dependencies
- tr
- sed
- date [GNU coreutils - '-d' and '@']
- awk
