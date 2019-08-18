# svn.sh
## description
subversion wrapper for adding additional work-flow helpers and simplification of various built-in calls

## usage
```
SYNTAX: svn_ OPTION [OPT_ARGS]

where OPTION:
  -l|--log [r]X [[r]X2]  : output commit log info for items / revision
                           described, with X a revision number, or the
                           limit of commits to output

    with supported X:
      [X : 1 <= X <= 25]   : last x commits (-l X)
      [X : X > 25]         : revision X (-c X)
      [+X : 1 <= X <= ..]  : revision X (-c X)
      [rX : 1 <= X <= ..]  : revision X (-c X)
      [-X : X <= -1]       : last X commits (-l X)
      [rX_1 rX_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision X_1 and revision X_2 inclusive
          (-r'min(X_1,X_2)'..'max(X_1,X_2)')
      [-X_1 -X_2 : 1 <= X_1/X_2 <= ..]
        : commits between revision 'HEAD - X_1' and revision
          'HEAD - X_2' inclusive (-r'-min(X_1,X_2)'..-'max(X_1,X_2)')

  -am|--amend ID  : amend log entry for commit ID
  -cl|--clean TARGET  : remove all '.svn' under TARGET
  -ign|--ignore PATH [PATH ..]  : add a list of paths to svn:ignore
  -rev|--revision  : output current revision
  -st|--status  : display an improved status of updated and new files
  -d|--diff [ID]  : take diff of ID (default PREV) against HEAD
  -fp|--format-patch ID TARGET  : format a patch for revision ID and
                                  written to TARGET
  -ra|--repo-add  : add a new repository to the server using an
                    existing template named 'temp'
  -rc|--repo-clone SOURCE_URL TARGET  : clone remote repository at
                                        SOURCE_URL to local TARGET
                                        directory
```
