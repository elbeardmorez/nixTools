# nixTools

## description
miscellaneous tools for 'nix systems. bash / zsh shells are tested, and as such, i'd guess ksh should work just fine too. follow the individual script links above their descriptions for further details

## notes
all scripts are currently in use to some extent, with 'backup.sh', 'challenge.sh', 'devel.sh' and 'git.sh' scripts in use on a daily basis

i assign all scripts the 'highly' coveted 'WIP / unreleased' status to garner sufficient 'caveat emptor' feeling in any would-be utiliser! there may very well be heinous bug(s) in there somewhere, but my assurance is simply that none are intentional, and the quantity per script should be inversely proportional to the love each has received in more recent days

no attempt at full POSIX compatibility will ever be made (hacks around lack of arrays / sourcing third-party code will never happen)

worthy of note, for that one person i might p@ss off.. the repository will certainly be re-written any time a 'new' (read 'old') script is dusted off and cleaned up sufficiently to warrant inclusion. apologies in advance for any additional key strokes!

lastly, bug reports are very welcome

## scripts

### [archive.sh](archive)
general purpose extractor and multi-volume tar wrapper to ease multi-volume archive creation and updating*

### [backup.sh](backup)
creates a 'hardlink-based' backup set comprising an arbitrary number of sets for each of the supported time interval types (hourly/daily/weekly/monthly or custom). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - **there is no duplication of identical** files, which is in essence its sole raison d'être

### [blog.sh](blog)
simple script for creating or modifying blog entry data stored as a basic key/value flat backend (file) format - cms / front-end agnostic. target blog stores can be listed directly, else via a menu system for displaying, selecting, and performing operations

### [bzr.sh](bzr)
bazaar wrapper for adding additional work-flow helpers and simplification of various built-in calls

### [challenge.sh](challenge)
coding challenge aid to simplify structuring of challenge files, creation of appropriate empty solution sets ready for editing and ultimately solution testing

### [dates.sh](dates)
date related functionality

### [devel.sh](devel)
miscellaneous development aids, wrappers and workflows

### [diff.sh](diff)
diff related functionality

### [file.sh](file)
'swiss-army knife' for all tasks file related.. well, a few tasks anyway. currently,  wrappers / routines for cleaning names (stripping leading / trailing chars, removing chars, changing case), removing duplicate lines, trimming lines, editing, dumping, duplicating and searching. target file(s) are set as either a directory of files, or those located (interactively where multiple are matched) through 'search.sh'

### [git.sh](git)
git wrapper adding several features and various customised calls to the underlying binary using minimal aliases. commands fall through to git binary

### [history.sh](history)
push a set of (command) strings to a target file. where no (command) strings are specified, commands are taken from the appropriate HISTFILE. (command) strings are verified prior to appending via a prompt which offers editing. the target file is located via the 'search.sh' script

### [increments.sh](increments)
given a search set and a target, find all files satisfying the search under/in the target and return a match list ordered by modification date to represent an incremental set, from which a dump of ordered incremental diffs is optionally created

### [math.sh](math)
bc wrapper adding miscellaneous functionality that is otherwise either painful to remember (e.g. base conversion), or painful to repeatedly implement (e.g. comparitors)

### [media.sh](media)
miscellaneous a/v functionality

### [search.sh](search)
ease location of your (regularly used) files. offers optionally interactive selection prompt for search match verification and for 'local' searches, target files are created where not found. thin wrapper around `find`, aimed for use with other onward scripts

### [slack.sh](slack)
script to aid in the building and installation of source and package based software on a Slackware 64 multilib system

### [socket.sh](socket)
netcat wrapper to simplify several use cases

### [svn.sh](svn)
subversion wrapper for adding additional work-flow helpers and simplification of various built-in calls
