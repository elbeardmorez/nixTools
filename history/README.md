# history.sh

## description
push a set of (command) strings to a target file. where no (command) strings are specified, commands are taken from the appropriate HISTFILE. (command) strings are verified prior to appending via a prompt which offers editing. the target file is located via the 'search.sh' script

## usage
```
SYNTAX: history_ [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'

where:

  OPTIONS can be:
    -h, --help  : this help information

  TARGET  : is a file to append commands to

  COMMANDs  : are a set of commands to verify

note: where no COMMAND args are passed, the file specified by
      HISTFILE will be used as a source
```
