# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. falls through to git binary otherwise

## usage
```
SYNTAX: git_ <OPTION> [OPTION-ARGS]

where <OPTION> can be:

  help  : print this text
  diff  : output diff to stdout
  log [N]   : print last N log entries, simple log format
  log1 [N]  : print last N log entries, single line log format
  logx [N]  : print last N log entries, extended log format
  sha <SEARCH> [N]  : return full sha for an id or partial
                      description string. searching by description
                      is limited to the last N (default: 50) commits
  st|status      : show column format status with untracked local
                   path files only
  sta|status-all : show column format status
  addnws  : add all files, ignoring white-space changes
  fp|format-patch <ID> [N]  : format N patch(es) back from an id or
                              partial description string
  rb|rebase <SEARCH> [N]  : interactively rebase by id or partial
                            description string. searching by
                            description is limited to the last N
                            (default: 50) commits
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
