# backup.sh

## description
creates a 'hardlink-based' backup set with 10 of each of the four time period granularities (hourly, daily, weekly, monthly). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - there is no duplication of **identical** files

## usage
```
SYNTAX: backup_ -I <SOURCES> [OPTIONS]

where:

  -I, --include <SOURCES>  : file containing source paths to backup,
                             one per line

and [OPTIONS] can be:

  -p, --period <PERIOD>  :  PERIOD can be either 'hourly', 'daily',
                            'weekly' or 'monthly'
  -f, --force  : force backups regardless of whether the period type's
                 epoch has elapsed since its previous update. this
                 will thus always roll the backup set along one
  -l, --limit  : limit to period specified only
  -r, --root  : specify the root of the backup set
  -v, --verbose  : verbose mode
  -h, --help  : this help info

environment variables:

  BACKUP_ROOT  : as detailed above
  RSYNC  : path to the rsync binary to use (default: auto)
  RSYNC_OPTIONS  : space delimited set of options to pass to rsync.
                   modifying this is very dangerous and may compromise
                   your backup set
                   (default: --archive --relative --delete --verbose)
```

## implementation
the hard work (the actual copying of files) is handled by the extremely impressive and mature **rsync** program. this wrapper simply uses this binary to construct backup sets at set time intervals, purging the last sets of each time period when any period hits the set limit (10)

by way of example, if running concurrent hourly backups (via cron, systemd etc), after 10 hours of use, the `hourly.10` backup folder is purged, all preceding folders in the set are then rolled back (`hourly.1` -> `hourly.2`) to make way for the latest backup set (`hourly.1`). the closest state to this purge set would then be found at the next time period granularity, i.e `daily.1`

the implementation requires a list of source directories in the rsync format. this allows for partial relative directory structures to be specified, e.g:
```
source              target
/root/./docs/       TARGET/docs
/var/./www/docs/    TARGET/www/docs
```

## rsync parameter reference

**default** / current options in use
```
-v, --verbose   : increase verbosity
--delete        : delete extraneous files from dest dirs
-R, --relative  : use relative path names
-a, --archive   : archive mode; equals -rlptgoD
which translates to:
  -r, --recursive  : implied by -a
  -l, --links      : copy symlinks as symlinks
  -p, --perms      : preserve permissions
  -t, --times      : preserve modification times
  -g, --group      : preserve group
  -o, --owner      : preserve owner (super-user only)
  -D               : same as --devices --specials
  which translates to:
    --devices   : preserve device files (super-user only)
    --specials  : preserve special files
```
miscellaneous, **non-default** options
```
-u, --update           : skip files that are newer on the receiver
-E, --executability    : preserve the file's executability
-X, --xattrs           : preserve extended attributes
-n, --dry-run          : don't actually copy/move/delete any files
--files-from=FILE      : read a list of source-file names from FILE
--no-R, --no-relative  : the relative path part of the source directory
```
**note**:
`--files-from=FILE`  is used to subset the source(s). be aware of the
implicit behavioural changes that this option will cause to others,
e.g. archive mode where, `--relative` and `--no-recursive` are then
implied, and as such additional `--no-relative` and `--recursive`
options would be needed to restore archive mode's usual characteristics.
consult *man(1) rsync* for full details

# dependencies
- rsync
- sed
- which
