# git.sh

## description
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. falls through to git binary otherwise

## usage
```
USAGE: git.sh <command> [command-args}

where <command> is:

  help      : print this text
  diff      : output diff to stdout
  log [n]   : print last n log entries, simple log format
  log1 [n]  : print last n log entries, single line log format
  logx [n]  : print last n log entries, extended log format
  st|status : show status with untracked in column format
  addws     : add all files, ignoring white-space changes
  addb      : add all files, ignoring space changes
  fp|formatpatch <ID> [n] : format n patch(es) by commit / description
  rb|rebase <ID>          : interactively rebase by commit / description
  cl|clone <REPO>         : clone repo
  co|checkout             : checkout files / branches
  c|commit                : add updated and commit
  ca|commitamend          : add updated and commit, amending last commit
  can|commitamendnoedit   : add updated and commit, amending last commit without editing commit message
  a|amend                 : amend previous commit
  an|amendnoedit          : amend previous commit without editing commit message
  ff|fast-forward         : identify current 'branch' and fast-forward to HEAD of 'linked'
```
