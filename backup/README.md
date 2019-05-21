# backup.sh

## description
creates a 'hardlink-based' backup set comprising an arbitrary number of sets for each of the supported time interval types (hourly/daily/weekly/monthly or custom). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - **there is no duplication of identical** files, which is in essence its sole raison d'être

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
  -p, --purge  : purge any extraneous backup sets found
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

**SOURCES**  
the implementation requires a list of source directories in the *rsync* format. this allows for partial relative directory structures to be specified, e.g:
```
source              target
/root/./docs/       TARGET/docs
/var/./www/docs/    TARGET/www/docs
```

**INTERVALS**  
the implementation allows for an arbitrary mix of *simple*, default supported built-in intervals types (currently: hourly, daily, weekly, monthly), *mixed*, which uses the pipe ('|') delimited double 'name|size' as an interval description, used specifically to override built-in max set sizes, and finally, *custom*, which use the pipe ('|') delimited triple/[quad] 'name|epoch|anchor[|size]' as an interval description. e.g.:
```
$ BACKUP_ROOT=/backup/live backup_ --verbose --intervals "15m|900 seconds|%d %b %Y %H:00:00"

$ BACKUP_ROOT=/backup/live backup_ --verbose --intervals "15m|15 minutes|%d %b %Y %H:30:00"
```
the above examples are identical, resulting in creation of backup sets at 15 minute intervals which will be anchored at 00, 15, 30, 45 minutes past the hour

both *epoch* and *anchor* must be datetime 'descriptions' recognised by **GNU coreutils**'s `date` binary - it is highly flexible, see `info date` for details. both parts are used to determine whether a backup should be performed or not. such a mechanism is more relevant (or even necessary!) in practice for creation of sets with longer term epochs, e.g. months

the problem with dumb timers is that they require the system to be operational either for the entire duration of the epoch, else, at that specific point in time that the backup should be made (e.g. 1st of the month).

this script requires each interval type / period is 'anchored' to a position in time, and then whenever the script is run, either directly specifying the target interval type, or via the default cascading, the decision to perform that backup or not is **based on the last anchor datetime**. therefore if your machine has been off a while, the next time the script is run, it'll notice it's past due for that backup type and perform it. the next update for that interval type may then occur in much less time than prescribed by the type's epoch/interval, but this potential unevenness of the interval structure should be seen as a positive feature - it's better than missed backups!

## examples

again, the examples here are to be called via a timer of some sort with a resolution less than or equal to the smallest epoch you desire support for, e.g. 1 hour by default

**simple, ultimately generates 10 hourly, daily, weekly and monthly incremental sets**
```
$ backup_
```

**testing**
```
$ DEBUG=1 BACKUP_ROOT=/backup/test backup_ -v --intervals "10m|10 minutes|%d %b %Y %H:00:00|6,hourly|12" -t hourly -f
```
- [`DEBUG=1`] show all step performed
- [`BACKUP_ROOT=/backup/live`] specify non-default backup folder
- [`-v`] verbose mode, 'human readable' description of steps
- [`---intervals "10m|10 minutes|%d %b %Y %H:00:00|6,hourly|12"`] max 6 10 minute backups, max 12 hourly backups

**force a new entry in the hourly backup set immediately**
```
$ backup_ --verbose --intervals "10m|10 minutes|%d %b %Y %H:00:00|6,hourly|12" -t hourly --force --no-casade
```
- [`-t hourly`] target 'hourly' interval backup set
- [`--force`] force the creation of the target set, ignoring current position in its epoch
- [`--no-cascade`] don't inadvertently update any other backup set

## implementation
if a backup program is defined simply as a file copier on a schedule, then this script should be viewed as a relatively thin wrapper over the **rsync** file copier which expects to be called via a scheduler like **cron**, or integrated into the likes of **systemd** via a timer, in order to operate as intended. the extremely impressive *rsync*, is very mature and as such very unlikely to cause problems at the business end of this wrapper (the actual file copying).

this wrapper uses the *rsync* binary to firstly construct a *master* backup set of all required files. it uses rsync's `--link-dest=DIR` option to ensure any unchanged files are hardlinked to the appropriate existing files in the backup set. providing a specific requested interval (or any interval representing a greater epoch when 'cascading' - which happens by default) has fully elapsed, it then makes a copy of this updated master set to that interval type. importantly, this mechanism maintains all hardlinks in the existing backup set revisions. there can be an arbitrary number of revisions for each interval type's set, the default is 10 where not specified.

when the max revisions limit is hit for an interval, the roll stage of the procedure will purge the last revision in the set. by way of example: if running concurrent hourly backups, then after 11 hours of use, the `hourly.10` folder, which will necessarily exist, will be removed, and all preceding folders in the set will then be rolled / 'pushed back' (`hourly.1` -> `hourly.2` etc.) to make way for the latest backup set (`hourly.1`). the backup set with the closest state to that of the purged set (`hourly.10`) would then be found in one of the backups for an interval type with greater time epoch, i.e `daily.1` in this instance*

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
- date (GNU coreutils)
