flock(1) -- lock file during command
====================================

## SYNOPSIS

`flock` [`-suno`] [`-w` secs] <file> <command> [<argument> ...]

`flock` [`-suno`] [`-w` secs] <file-descriptor-number>

## DESCRIPTION

This utility manages flock(2) locks from within shell scripts or the
command line.

The first forms wrap the lock around the executing a command, in a
manner similar to su(1) or newgrp(1). It locks a specified file or
directory, which is created (assuming appropriate permissions), if it
does not already exist.  By default, if the lock cannot be immediately
acquired, **flock** waits until the lock is available.  By default,
	**flock** uses an an exclusive lock, sometimes called a write lock.


The second form uses open file by file descriptor number.  See **EXAMPLES**
for how that can be used.

## OPTIONS

* `-s`:
	Obtain a shared lock, sometimes called a read lock, instead of the
	default exclusive lock.
* `-o`:
	Close the file descriptor on which the lock is held before executing
	**command**. This is useful if **command** spawns a child process which
	should not be holding the lock.
* `-n`:
	Fail rather than wait if the lock cannot be immediately acquired.
* `-w` <seconds>:
	Fail if the lock cannot be acquired within **seconds**. Decimal
	fractional values are allowed.
* `-u`:
	Drop a lock.  This is usually not required, since a lock is
	automatically dropped when the file is closed.  However, it may be
	required in special cases, for example if the enclosed command group
	may have forked a background process which should not be holding
	the lock.


## EXAMPLES

Lock `/tmp` while running the utility `cat`:

		flock /tmp cat

Lock `local-lock-file` exclusively while running the utility `echo` with `'a b c'`.

		flock local-lock-file echo 'a b c'

Set exclusive lock to directory `/tmp` and the second command will fail.

		flock -w .007 /tmp echo; /bin/echo $?
		flock -s /tmp -c cat

Set shared lock to directory `/tmp` and the second command will not fail.
Notice that attempting to get exclusive lock with second command
would fail.

		flock -s -w .007 /tmp -c echo; /bin/echo $?
		flock -s /tmp -c cat

This is useful boilerplate code for shell scripts.  Put it at the top of
the shell script you want to lock and it'll automatically lock itself on
the first run.  If the env var `FLOCKER` is not set to the shell script
that is being run, then execute flock and grab an exclusive non-blocking
lock (using the script itself as the lock file) before re-execing itself
with the right arguments.  It also sets `FLOCKER` to the right value so
it doesn't run again.

		[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -n "$0" "$0" "$@" || :

Using a file descriptor with a shell block is useful for locking
critical regions inside shell scripts. If the shell process has
permission to write or create the lockfile, `>` allows the lockfile to
be created if it does not exist. If the process only has read
permission, `<` allows the file to already exist but only read
permission is required.

		(
				flock -n 8 || exit 1
				# commands executed under lock ...
		) 8> /var/lock/mylockfile

## EXIT STATUS

The command uses `sysexits.h` return values for everything, except when
using either of the options `-n` or `-w` which report a failure to
acquire the lock with a return value of `EXIT_FAILURE`.

When using the **command** variant, and executing the child worked, then
the exit status is that of the child command.

## SEE ALSO

flock(2),
fcntl(2),
setpgrp(1),
nohup(1),
nice(1),
su(1)

## HISTORY

A flock(1) command was almost simultaneously created by
Adam J. Richter <adam@yggdrasil.com> sometime before 2004-11 and
H. Peter Anvin <hpa@zytor.com> in 2003-03.
