# backup.sh

## description
creates a 'hardlink-based' backup set with 10 of each of supported time interval types (hourly/daily/weekly/monthly or custom). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - **there is no duplication of identical** files, which is in essence its sole raison d'être

## usage
```
SYNTAX: backup_ [OPTIONS]

where [OPTIONS] can be:

  -s, --sources <SOURCES>  : file containing source paths to backup,
                             one per line
                             (default: 'BACKUP_ROOT/.include')
  -i, --intervals <INTERVALS>  : comma-delimited list of interval
                                 types. custom intervals are supported,
                                 see README for details
                                 (default: 'hourly,daily,weeky,
                                            monthly')
  -t, --type <TYPE>  : initiate backup from TYPE interval, where TYPE
                       is a member of the INTERVALS set (default: first
                       item in (epoch size ordered) INTERVALS list)
  -f, --force  : force backup regardless of whether the interval type's
                 epoch has elapsed since its previous update. this
                 will thus always roll the backup set along one. this
                 has no effect on cascaded interval types
  -nc, --no-cascade  : update only the specified interval type's set
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

### SOURCES
the implementation requires a list of source directories in the *rsync* format. this allows for partial relative directory structures to be specified, e.g:
```
source              target
/root/./docs/       TARGET/docs
/var/./www/docs/    TARGET/www/docs
```

### INTERVALS
the implementation allows for an arbitrary mix of simple default supported intervals types (currently: hourly, daily, weekly, monthly) or custom types which must be entered as triples via two additional suffixed pipe ('|') delimited arguments representing an interval as 'name|epoch|anchor'. e.g.:

```
$ BACKUP_ROOT=/backup/live backup_ --verbose --intervals "15m|900 seconds|%d %b %Y %H:00:00"

```
the above example allowing creation of backup sets at 15 minute intervals

## implementation
if a backup program is defined simply as a file copier on a schedule, then this script should be viewed as a relatively thin wrapper over the **rsync** file copier which expects to be called via a scheduler like **cron**, or integrated into the likes of **systemd** via a timer, in order to operate as intended. the extremely impressive *rsync*, is very mature and as such very unlikely to cause problems at the business end of this wrapper (the actual file copying).

this wrapper uses the *rsync* binary to firstly construct a *master* backup set of all required files. it uses rsync's `--link-dest=DIR` option to ensure any unchanged files are hardlinked to the appropriate existing files in the backup set. providing a specific requested interval (or any interval representing a greater epoch when 'cascading' - which happens by default) has fully elapsed, it then makes a copy of this updated master set to that interval type. importantly, this mechanism maintains all hardlinks in the existing backup set revisions. there can be up to 10 revisions for each interval type's set.

when the max revisions limit is hit for an interval, the roll stage of the procedure with purge the last revision in the set. by way of example: if running concurrent hourly backups, then after 11 hours of use, the `hourly.10` folder, which will necessarily exist, will be removed, and all preceding folders in the set will then be rolled / 'pushed back' (`hourly.1` -> `hourly.2` etc.) to make way for the latest backup set (`hourly.1`). the backup set with the closest state to that of the purged set (`hourly.10`) would then be found in one of the backups for an interval type with greater time epoch, i.e `daily.1` in this instance*

it's worth pointing out that purging of the final revision set will only 'delete' a file if it is nowhere common across the rest of the backup set. where files are common, their link counts will just reduce by one.


*\*note: this is not guaranteed to be in a sensible location (as given by the example) where use of the `--force` switch has been made on the backup set. forcing a backup for a given interval type breaks the minimal time epoch separation between backups in that set, thus potentially making it more difficult to find a specific version*

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
