# archive.sh

tar wrapper to ease multi-volume archives and updating

## usage
```
usage: ./archive.sh [mode] [type] [options] [archive(s)]

mode:

 add:  creation / addition [tar only]

  options:
	   --split	size (MB) to use for splitting archive into multiple volumes
	   --name		archive name

 update:  [tar only]

 extract:  extract [multiple] archive files

  options:
	   [-t 'target directory']  : extract to target directory
	  'archive(s)  : archive files / directory containing archive files'
```

## implementation

the two shortcomings to tar as a stand-alone backup solution were its updating and multi-volume idiosyncrasies

the first, tar's concept of an 'update' is with respect to the archive itself.. anything you do which changes the archive and it is deemed an 'update'. when running `tar --update` with an existing archive and target, tar actually appends any modified files as opposed to truly updating them, thus leading to ever growing archives which was not what was desired

thus i was looking at some extensive list comparison with the need to identify additional files for addition, removed files for removal, and modified files for removal and then re-addition

some parsed rendition of `find $TARGET/$PATH -name * -exec stat {} \;` vs `tar --list` was anticipated, but ultimately `tar --diff` suffices given its output allows for easy identification of the files that need removing for reasons of either deletion or modification. excellent

the second, was that the multi-volume mechanism required either repeated calls / user input / intervention or an appropriate 'helper script'

once upon a time way back when, this was suitable / necessary given 'a tape' would need physically removing and replacing with the next (empty) tape when full, and the process manually continued following that exchange

the little 'multi.volume script' is trivial, but it would be totally unpalatable to write from scratch any time multi-volume backups were desired!
