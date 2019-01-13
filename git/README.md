# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. falls through to git binary otherwise

## usage
```
USAGE: _git <command> [command-args}

where <command> is:

  help  : print this text
  diff  : output diff to stdout
  log [n]   : print last n log entries, simple log format
  log1 [n]  : print last n log entries, single line log format
  logx [n]  : print last n log entries, extended log format
  st|status : show status with untracked in column format
  addnws  : add all files, ignoring white-space changes
  fp|formatpatch <ID> [n]  : format n patch(es) by commit / description
  rb|rebase <ID>  : interactively rebase by commit / description
  cl|clone <REPO>  : clone repo
  co|checkout      : checkout files / branches
  ca|commitamend         : commit, amending previous
  can|commitamendnoedit  : commit, amending previous without editing message
  ac|addcommit               : add updated and commit
  aca|addcommitamend         : add updated and commit, amending previous
  acan|addcommitamendnoedit  : add updated and commit, amending previous without editing message
  ff|fast-forward  : identify current 'branch' and fast-forward to HEAD of 'linked'
  rd|rescue-dangling  : dump any orphaned commits still accessable to a 'commits' directory
```
