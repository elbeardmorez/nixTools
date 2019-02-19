# history.sh

## description
push a set of (command) strings to a target file. where no (command) strings are specified, commands are taken from the appropriate HISTFILE. (command) strings are verified prior to appending via a prompt which offers editing. the target file is located via the 'search.sh' script

## usage
```
SYNTAX: history_ [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'

where:

  OPTIONS can be:
    -h, --help  : this help information
    -c COUNT, --count COUNT  : read last COUNT history entries
                               (default: 10)

  TARGET  : is a file to append commands to

  COMMANDs  : are a set of commands to verify

note: where no COMMAND args are passed, the file specified by
      HISTFILE will be used as a source
```

## implementation
possibly overkill to offer any remarks here given the simplicity of the solution, however, worth noting is that this wrapper had to try harder than one would have otherwise thought necessary to work with the history at all, and it's by no means a perfect solution in any case.

shells usually offer history control functionality, Bash's built-in `history` command is great, but by default only in the current session. running `history` in a `#!/bin/sh` sh-bang, yields nothing, Bash's POSIXifying special *sh*-mode ensures history is disabled, as is the case for any non-interactive shell calls e.g. through scripts. but what about if the interactive `-i` arg / switch is specified explicitly? well yes, until you need to do anything with the output, which will involve redirection of pipes (stdout), from which Bash initialisation can then deduce that it is not strictly running as an interactive shell (as it's main in/out pipeline is not connected to terminal fds) and thus it disables history functionality once again. passing Bash its `set -o history` does force the mechanism to work though. so why not use it? well because it has little advantage and more overhead than a simple `tail` of the history file. the one thing i'd hoped it might do is provide access to the current calling shell's cache (i.e. not yet persisted) command set, as it's that that usally contains the (latest) set of commands one would want to persist somewhere. however, alas it doesn't.

similarly, the POSIX `fc` requires an explicit call `fc -R` before any `fc -l` commands yield the goods. that's a massive overhead with a 100k (lines) history file. again, might as well just `tail` it.

hence this implementation sticks with the fairly generic 'identify current shell's history file and go from there' routine. it assumes that interactive shells are sufficiently user oriented - e.g. parse sufficient setup files, to provide the all important `HISTFILE` environment variable for extraction.

note that where you don't have your shell setup to automatically sync your shell activities to the HISTFILE on-the-fly (e.g. zsh's default setup?!), calling the likes of `history -a` prior to use of this script could be an option, or as an alias `alias history_="history -a && history_"`, else one could pass the commands through xargs with `history 10 | xargs sh -c 'history_ ./x < /dev/tty'` (noting the requirement to re-open stdin in the subprocess to facilitate user input).
