# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. commands fall through to git binary

## usage
```
SYNTAX: git_ OPTION [OPT_ARGS] [-- [BIN_ARGS]]*

where OPTION:

  -h|--help  : print this help information
  -d|--diff  : output diff to stdout
  -logTYPE [N] [ID]  : print log entries

    TYPE
      ''  :  simple log format
      1   :  single line log format
      x   :  extended log format
    [N]  : limit the number of results
    [ID]  : return results back starting from an id or partial
            description string. implies N=1 unless N specified

  -sha <ID> [N] [LOGTYPE]  : return commit sha / description for an id
                             or partial description string. use N to
                             limit the search range to the last N
                             commits. use LOGTYPE to switch output
                             format type as per the options above
  -st|--status      : show column format status with untracked local
                      path files only
  -sta|--status-all : show column format status
  -anws|--add-no-whitespace  : stage non-whitespace-only changes
  -fp|--format-patch [OPTION] [ID]
    : format one or more commits as patch file(s) up to a specified
      id or partial description string (default: HEAD)

    where OPTION:
      [-l|--limit] N  : format N patches up to the target ID
      -r|--root  : format all patches in current branch

  -rb|--rebase <ID> [N]  : interactively rebase back from id or partial
                           description string. use N to limit the search
                           range to the last N commits
  -rbs|--rebase-stash <ID> [N]  : same as 'rebase', but uses git's
                                 'autostash' feature
  -b|--blame <PATH> <SEARCH>  : filter blame output for PATH on SEARCH
                                and offer 'show' / 'rebase' options per
                                match
  -cl|-clone <REPO>  : clone repo
  -co|--checkout     : checkout files / branches
  -c|--commit                 : commit
  -ca|--commit-amend          : commit, amending previous
  -can|--commit-amend-noedit  : commit, amending previous without
                                editing message
  -ac|--add-commit                : add updated and commit
  -aca|--add-commit-amend         : add updated and commit, amending
                                    previous commit message
  -acan|-add-commit-amend-noedit  : add updated and commit, amending
                                    previous without editing message
  -ff|--fast-forward  : identify current 'branch' and fast-forward to
                        HEAD of 'linked'
  -rd|--rescue-dangling  : dump any orphaned commits still accessable
                           to a 'commits' directory
  -dc|--date-check TYPE [OPTIONS] TARGET

    where TYPE :
      order  : highlight non-chronological TARGET commit(s)
      timezone  : highlight TARGET commit(s) with invalid timezone
                  given locale's daylight saving rules

    and OPTIONS can be:
      -dt|--date-type TYPE  : check on date type TYPE, supporting
                              'authored' (default) or 'committed'
      -i|--issues  : only output highlighted commits

  -ds|--date-sort  : rebase all commits in current branch onto an
                     empty master branch of a new repository in a
                     date sorted order

  -smr|--submodule-remove <NAME> [PATH]  : remove a submodule named
                                           NAME at PATH (default: NAME)
  -fb|--find-binary  : find all binary files in the current HEAD

*note: optional binary args are supported for commands:
       log, rebase, formatpatch, add-no-whitespace, commit
```
