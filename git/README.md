# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. falls through to git binary otherwise

## usage
```
SYNTAX: git_ <OPTION> [OPTION-ARGS]

where <OPTION> can be:

  help  : print this text
  diff  : output diff to stdout
  log<TYPE> [N] [ID]  : print log entries

    <TYPE>
      ''  :  simple log format
      1   :  single line log format
      x   :  extended log format
    [N]  : limit the number of results
    [ID]  : return results back starting from an id or partial
            description string. implies N=1 unless N specified

  sha <ID> [N] [LOGTYPE]  : return commit sha / description for an id
                            or partial description string. use N to
                            limit the search range to the last N
                            commits. use LOGTYPE to switch output
                            format type as per the options above
  st|status      : show column format status with untracked local
                   path files only
  sta|status-all : show column format status
  addnws  : add all files, ignoring white-space changes
  fp|format-patch <ID> [N]  : format N patch(es) back from an id or
                              partial description string
  rb|rebase <ID> [N]  : interactively rebase back from id or partial
                        description string. use N to limit the search
                        range to the last N commits
  cl|clone <REPO>  : clone repo
  co|checkout      : checkout files / branches
  ca|commit-amend          : commit, amending previous
  can|commit-amend-noedit  : commit, amending previous without editing
                             message
  ac|add-commit                 : add updated and commit
  aca|add-commit-amend          : add updated and commit, amending
                                  previous commit message
  acan|add-commit-amend-noedit  : add updated and commit, amending
                                  previous without editing message
  ff|fast-forward  : identify current 'branch' and fast-forward to
                     HEAD of 'linked'
  rd|rescue-dangling  : dump any orphaned commits still accessable to
                        a 'commits' directory
```
