# nixTools

### [archive.sh](archive)
general purpose extractor and multi-volume tar wrapper to ease multi-volume archive creation and updating*

### [backup.sh](backup)
creates a 'hardlink-based' backup set comprising an arbitrary number of sets for each of the supported time interval types (hourly/daily/weekly/monthly or custom). the use of hardlinks means the disk space footprint for the incremental sets is kept to a minimum - **there is no duplication of identical** files, which is in essence its sole raison d'être

### [blog.sh](blog)
simple script for creating or modifying blog entry data stored as a basic key/value flat backend (file) format - cms / front-end agnostic. target blog stores can be listed directly, else via a menu system for displaying, selecting, and performing operations

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

### [search.sh](search)
ease location of your (regularly used) files. offers optionally interactive selection prompt for search match verification and for 'local' searches, target files are created where not found. thin wrapper around `find`, aimed for use with other onward scripts

### [slack.sh](slack)
script to aid in the building and installation of source and package based software on a Slackware 64 multilib system

### [socket.sh](socket)
netcat wrapper to simplify several use cases
