# socket.sh

## description
netcat wrapper to simplify several use cases

## usage
```
SYNTAX: socket_ [OPTION] [ARGS]

where OPTION can be:
  in [ARGS]  : server side socket setup for netcat
    where ARGS can be:
    -ps, --persistent  : leave connection open by default the
                         script exits after the first payload is
                         received
    -nc, --noclean  : don't even ask to delete existing blobs in
                      current directory

  out [ARGS] [DATA [DATA2 ..]]  : (default) client side socket
                                  setup for netcat
    where ARGS can be:

    -s, --server ADDRESS  : specify the target server address
                            (default: localhost)
    -r, --retries COUNT  : set the number retries when a push fails
                           (default: 10)
    -a, --any  : process non-file/dir args as valid raw data strings
                 to be push to the server

  and DATA args are either file / directory paths, or raw data (using
  '-a' / '--any' switch)

  environment variables:
 'SERVER' (client)  : as detailed above
 'PORT' (server / client)  : set communication port (default: 666)
 'SERVER_TIMEOUT'  : in non-persistent mode, the server side will
                     automatically terminate after this interval
                     where no packets are received (default: 60)
```

## dependencies
- Bourne-like shell (various non-POSIX shell features)
- GNU netcat
- sed
- tar
- file
