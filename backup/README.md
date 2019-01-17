# backup.sh

## implementation
read files which state the last backup up time for 'period' of backup, and decide whether the backup is required or not
we want to perform backup to the nearest hour, day

multiple src directories ..was looking at including from a file by creating an array of '\n' delimited entries. i'd have
append and prepend '"'s to each path to create a string that could be used as as a parameter to rsync command to safegaurd
against slitting directories with spaces in the name!

RSYNCOPTIONS=( "-varR" "--delete" )

rsync parameters
-a, --archive  : implies -rlptgoD
-r, --recursive  : implied by -a
-R, --relative  : use relative path names
-u, --update  : skip files that are newer on the receiver
-v, --verbose
-t, --times  : preserve modification times
-p, --perms  : preserve permissions
-E, --executability  : preserve executabilit
-X, --xattrs  : preserve extended attributes
-o, --owner  : preserve owner (super-user only)
-g, --group  : preserve group
-n, --dry-run  : dont actually copy/move/delete any files
-l, --links  : copy symlinks as symlinks
--files-from  : change the meaning of -a  ..need to append --no-R
--no-R : the relative path part of the source directory is not kept

--files-from doesn't work the way i want it to. ..it's files relative to the source directory
