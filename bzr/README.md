# bzr.sh
## description
bazaar wrapper for adding additional work-flow helpers and simplification of various built-in calls

## usage
```
SYNTAX: bzr_ [OPTION]

with OPTION:

  log [r]X [[r]X2]  : output log information for commit(s) X:

    with supported X:
      [X : 1 <= X <= 25]  : last x commits (-r-X..)
      [X : X > 25]        : revision X (-rX)
      [+X : 1 <= X <= ..] : revision X (-rX)
      [rX : 1 <= X <= ..] : revision X (-rX)
      [-X : X <= -1]      : last X commits (-r-X..)
      [rX_1 rX_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision X_1 and revision X_2 inclusive
          (-r'min(X_1,X_2)'..'max(X_1,X_2)')
      [-X_1 -X_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision 'HEAD - X_1' and revision
          'HEAD - X_2' inclusive (-r'-min(X_1,X_2)'..-'max(X_1,X_2)')

  diff [REVISION]  : show diff of REVISION again previous
                     (default: HEAD)
  patch [REVISION] [TARGET]  : format REVISION (default: HEAD) as a
                               diff patch file with additional
                               context information inserted as a
                               header to TARGET (default: auto-
                               generated from commit message)
  commits [SEARCH] [TYPE]  : search log for commits containing SEARCH
                             in TYPE field

    with support TYPE:
      message  : search the message content (default)
      author  : search the author field
      committer  : search the commiter field

  commits-dump TARGET [SEARCH] [TYPE]
    : wrapper for 'commits' which also dumps any matched commits
      to TARGET
```
