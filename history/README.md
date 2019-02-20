# history.sh

## description
push a set of (command) strings to a target file. where no (command) strings are specified, commands are taken from the appropriate HISTFILE. (command) strings are verified prior to appending via a prompt which offers editing. the target file is located via the 'search.sh' script

## usage
```
SYNTAX: history_ [OPTIONS] TARGET [COMMAND [COMMAND2.. ]]'

where:

  OPTIONS can be:
    -h, --help  : this help information
    -c [COUNT], --count [COUNT]  : read last COUNT history entries
                                   (default: 10)
    -s. --silent  : disable info messages

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

where you don't have your shell setup to automatically sync your shell activities to the HISTFILE on-the-fly (e.g. zsh's default setup?!), calling the likes of `history -a` prior to use of this script could be an option, or as an alias `alias history_="history -a && history_"`, else one could pass the commands through xargs with `history 10 | xargs -I{} sh -c "history_ ./x '{}'"` (note: the script now ensures that its stdin is pointing at a usable terminal for requesting user input, hence redirection of its stdin by the calling (parent) process (e.g. when piping commands) will work without any need to explicitly reset it for the subshell process (e.g. by suffixing `< /dev/tty` in the above command).

## examples
```
$ history -10 | history_ -s -c 5 history_.examples '# history_ sessions'
[info] no matches for search 'history_.examples'

$ history -10 | history_ -s -c 5 ./history_.examples '# history_ sessions'
[user] file './history_.examples' does not exist, create it? [y/n]: y
[user] append command '# history_ sessions?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]:

...

$ history -20 | history_ -c 5 history_.examples '# history_ sessions'
[info] added 1 command from args
[info] added 5 commands from stdin
[info] added 5 commands from history file '/root/.bash_history'
[info] target file 'history_.examples' set
[info] 11 commands for consideration
[user] append command '# history_ sessions?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'git stash pop?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: n
[user] append command 'history -10 | DEBUG=1 sh -c "history_ -c 3 ./x 'abc > 123'"?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'git add -p?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: n
[user] append command 'git commit --amend --no-edit?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: n
[user] append command 'git log?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: n
[user] append command 'history -10 | sh -c "history_ -c 3 ./x 'abc > mip'"?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'history -10 | history_ -c 5 ./x '# history sessions'?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'history -10 | xargs -I'{}' bash -c 'history_ ./x "{}" < /dev/tty'?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'history -10 | xargs bash -c 'history_ ./x < /dev/tty'?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
[user] append command 'history -10 | xargs sh -c 'history_ ./x < /dev/tty'?' [(y)es/(n)o/(e)dit/(a)ll/e(x)it]: y
```
