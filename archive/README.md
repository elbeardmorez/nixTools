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
