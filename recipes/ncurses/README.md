# Host terminfo compatibility

Mixed-case terminfo installation uses letter subdirectories such as `x/xterm`
rather than hexadecimal directories such as `78/xterm`. This matches Linux host
databases and lets `TERMINFO` select host entries such as `xterm-ghostty` while
retaining the packaged database. The recipe's installed test compiles and reads
a separate host-style database to cover this interface.
