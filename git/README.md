# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. commands fall through to git binary

## usage
```
SYNTAX: git_ OPTION [OPT_ARGS] [-- [BIN_ARGS]]*

where OPTION:

  --help  : print this help information
  --diff  : output diff to stdout
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
  -fp|--format-patch [ID] [N]  : format N patch(es) back from an id or
                                 partial description string
                                 (default: HEAD)
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
  -doc|--dates-order-check [OPTIONS] TARGET
    : highlight non-chronological TARGET commit(s)

    where OPTIONS can be:
      -t|--type TYPE  : check on date type TYPE, supporting 'authored'
                        (default) or 'committed'
      -i|--issues  : only output non-chronological commits

  -smr|--submodule-remove <NAME> [PATH]  : remove a submodule named
                                           NAME at PATH (default: NAME)

*note: optional binary args are supported for commands:
       log, rebase, formatpatch, add-no-whitespace, commit
```
