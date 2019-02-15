# nixTools

### [backup.sh](backup)
creates a 'hardlink-based' backup set comprising an arbitrary number of sets for each of the supported time interval types (hourly/daily/weekly/monthly or custom). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - **there is no duplication of identical** files, which is in essence its sole raison d'être

### [challenge.sh](challenge)
structures challenge files and opens a set of empty solution files in an editor

### [dates.sh](dates)
date related functionality

### [diff.sh](diff)
diff related functionality

### [git.sh](git)
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. commands fall through to git binary

### [increments.sh](increments)
given a search set and a target, find all files satisfying the search under/in the target and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is optionally created

### [search.sh](search)
ease location of your (regularly used) files. offers optionally interactive selection prompt for search match verification and for 'local' searches, target files are created where not found. thin wrapper around `find`, aimed for use with other onward scripts

### [slack.sh](slack)
script to aid in the building and installation of source and package based software on a Slackware 64 multilib system

### [socket.sh](socket)
netcat wrapper to simplify several use cases
