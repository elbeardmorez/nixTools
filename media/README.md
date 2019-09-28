# media.sh

## description
miscellaneous a/v functionality

## usage
```
SYNTAX: media_ [OPTION]

where OPTION:

  -p|--play TARGET  : play media file(s) found at TARGET

    TARGET  : a target file / directory or a partial file name to
              search for

  -s|--search [OPTION] SEARCH : search for file(s) in known locations

    OPTION:
      -i|--interactive  : prompt to complete search on first valid
                          results set
      -ss|--substring-search  : search progressively shorter substring
                                of the search term until match
    SEARCH  : a (partial) match term

  -i|--info [LEVEL]  : output formatted information on file(s)

    LEVEL  : number [1-5] determining the verbosity of information
             output

  -a|--archive [LEVEL] [SOURCE]
    : recursively search a directory and list valid media files with
      their info, writing all output to a file

    LEVEL  : number [1-5] determining the verbosity of information
             output
    SOURCE  : root directory containing media files to archive

  -str|--structure SEARCH [FILTER [FILTER2.. [FILTERx]]]
    : create a standardised single / multi-file structure for matched
      file(s) under the current working directory

    SEARCH  : a (partial) match term
    FILTER  : strings to remove from matched file names for a
              multi-file structure

  -r|--rate SEARCH RATING  : rate media and move structures to the
                             nearest ratings hierarchies

    SEARCH  : a (partial) match term
    RATING  : numeric rating (eg. 1-10), to push the structure to /
              under in a ratings hierarchy

  -rec|--reconsile LIST  : match a list of names / files in list to
                           media at known locations and write results
                           to an adjacent file

    LIST  : file containing names / files strings to search for

  -f|--fix TARGET  : fix a stream container

    TARGET  : the broken flv media file

  --kbps VSIZE ASIZE LENGTH  : calculate an approximate vbr for a
                               target file size

    VSIZE[M|b]  : target video size in either megabytes ('M' suffix)
                  or bytes ('b' suffix / default)
    ASIZE[M|b]  : target audio size in either megabytes ('M' suffix)
                  or bytes ('b' suffix / default)
    LENGTH[m|s]  : length of stream in either minutes ('m' suffix /
                   default) or seconds ('s' suffix)

  -rmx|--remux TARGET [PROFILE] [WIDTH] [HEIGHT] [VBR] [ABR]
                        [PASSES] [VSTREAM] [ASTREAM]
    : ffmpeg wrapper for changing video dimensions and / or a/v codecs

    TARGET  : file to remultiplex
    PROFILE  : profile name (default: '2p6ch')
    WIDTH  : video width dimension (default: auto)
    HEIGHT  : video height dimension (default: auto)
    VBR  : video bitrate (default: 1750k)
    ABR  : audio bitrate (default: 320k)
    PASSES  : perform x-pass conversion of stream (x: 1 or 2)
    VSTREAM  : set video stream number (default: 0)
    ASTREAM  : set audio stream number (default: 0)

  -syn|--sync TARGET OFFSET  : (re-)synchronise a/v streams by
                                 applying an offset

    TARGET  : file to synchronise
    OFFSET  : numeric offset in milliseconds

  -e|--edit [TARGET] [FILTER]  : demux / remux routine

    TARGET  : directory containing video files to demux or multiple
            demuxed stream files (*.vid | *.aud) to concatenate and
            multiplex (default: '.')
    FILTER  : whitelist match expression for sed (default: '.*')

  -n|--names SET [LIST]  : rename a set of files, based on a
                           one-to-one list of pipe ('|') delimited
                           templates of the form '[#|]#|NAME' in a
                           file

    SET  : common prefix for all resultant file names
    LIST  : file containing templates (default: './names')

  -pl|--playlist LIST  : interactively cycle a list of filenames and
                         play the subset which begins with the
                         selected item

    LIST  : file containing file paths to cycle

  --rip TITLE  : extract streams from dvd media

    TITLE  : name used for output files

# environment variables:

## global
DEBUG  : output debug strings of increasingly verbose nature
         (i.e. DEBUG=2)
TEST  : '--structure'|'--names', perform dry-run (i.e. TEST=1)
REGEX  : '--search' (and derivatives), override default 'glob'
         search mechanism (i.e. REGEX=1)
ROOTDISK  : root directory containing disk mounts (default: '/media')
ROOTISO  : root of cd / dvd mount (default: '/media/iso')
PATHMEDIA  : path to media store (default: '$HOME/media')
PATHMEDIATARGETS  : pipe-delimited ('|') list of targets paths, full
                    paths, '$PATHMEDIA' relative paths and glob names
                    supported
PATHRATINGSDEFAULT  : path to ratings structure
                      (default: '$PATHMEDIA/watched')
PATHARCHIVELISTS  : path to archive list(s), either full path(s) or
                    '$PATHMEDIATARGETS' relative path(s), falling back
                    to '$PATHMEDIA' relative path(s) supported
                    (default: 'archives/')

## option specific
FILTERS_EXTRA [--structure]  : additional string filter expession for
                               sed of the form 'SEARCH/REPLACE'
VIDEO [--rip]  : override subtitle track extracted (default: 1)
AUDIO [--rip]  : override subtitle track extracted (default: 1)
SUBS [--rip]  : override subtitle track extracted (default: 1)
CMDPLAY [--play|--playlist]  : player binary (default: 'mplayer')
CMDPLAY_OPTIONS [--play|--playlist] :  player options (default: '-tv')
CMDPLAY_PLAYLIST_OPTIONS  [--play|--playlist]
  : player specific option required for playlist mode (default: '-p ')
CMDFLVFIXER [--fix]  : 'flvfixer' script path
PLAYLIST [--playlist]
  : playlist file (default: '/tmp/$CMDPLAY.playlist)
```