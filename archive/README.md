# archive.sh

## description
general purpose extractor and multi-volume tar wrapper to ease multi-volume archive creation and updating*

*see implementation for further detail

## usage
```
SYNTAX: ./archive.sh [-h] [MODE] [OPTIONS]

  -h, --help  : print this help information

  MODE:

    a, add:  create a tar archive

      SYNTAX: ./archive.sh --add --name NAME --target TARGET [OPTIONS]

      NAME:  achive name
      TARGET:  path to files for addition
      OPTIONS:
        -mv, --multi-volume  : assume multi-volume archive
        -s, --split  : max size (MB) to use for splitting archive into
                       multiple volumes

      support: tar only

    u, update:  update a tar archive

      SYNTAX: ./archive.sh --update --name NAME --target TARGET [OPTIONS]

      NAME:  achive name
      TARGET:  path to files for addition / update
      OPTIONS:
        -mv, --multi-volume  : assume multi-volume archive

      support: tar only

    x, extract:  extract [multiple] archive files

      SYNTAX: ./archive.sh --extract [OPTIONS] TARGETS

      OPTIONS:
        -d, --dest PATH  : extract to PATH
      TARGETS:  one or more archive files and/or directories
                containing archive file(s)

      support:  tar [.tar], gzip [.gz], zx [.xz], bzip2 [.bzip2/.bz2], tar 
                (gzip/bzip2/xz/lz) [.tar.gz/.tgz/.tar.bz2/.tbz2/.tar.xz/.txz], 
                rar [.rar], zip [.zip], Lempel-Ziv [.Z], 7zip [.7z], redhat 
                package manager package [.rpm], WinAce [.ace], lzma [.lzma], 
                iso9660 image [.iso], DebIan package [.deb], java package [.jar]
```

## implementation

the two shortcomings to tar as a stand-alone backup solution were its updating and multi-volume idiosyncrasies

the first, tar's concept of an 'update' is with respect to the archive itself.. anything you do which changes the archive and it is deemed an 'update'. when running `tar --update` with an existing archive and target, tar actually appends any modified files as opposed to truly updating them, thus leading to ever growing archives which was not what was desired

thus i was looking at some extensive list comparison with the need to identify additional files for addition, removed files for removal, and modified files for removal and then re-addition

some parsed rendition of `find $TARGET/$PATH -name * -exec stat {} \;` vs `tar --list` was anticipated, but ultimately `tar --diff` suffices given its output allows for easy identification of the files that need removing for reasons of either deletion or modification. excellent

the second, was that the multi-volume mechanism required either repeated calls / user input / intervention or an appropriate 'helper script'

once upon a time way back when, this was suitable / necessary given 'a tape' would need physically removing and replacing with the next (empty) tape when full, and the process manually continued following that exchange

the little 'multi.volume script' is trivial, but it would be totally unpalatable to write from scratch any time multi-volume backups were desired!

## dependencies
- which

### optional
- GNU tar
- gzip [gunzip, uncompress]
- bzip [bzip2]
- zip [unzip]
- xz
- WinRAR [unrar]
- 7-zip [7za]
- WinAce [unace]
- Java SDK / RE [jar]
- msitools [msiextract]
- binutils [ar]
- util-linux [mount]
