#ifdef S_SPLINT_S
#define __x86_64__
#endif

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sysexits.h>
#include <unistd.h>
#include <stdbool.h>

#ifndef HAVE_FLOCK
/* lock operations for flock(2) */
#define	LOCK_SH		0x01		/* shared file lock */
#define	LOCK_EX		0x02		/* exclusive file lock */
#define	LOCK_NB		0x04		/* don't block when locking */
#define	LOCK_UN		0x08		/* unlock file */

/* The following flock() emulation snarfed intact *) from the HP-UX
 * "BSD to HP-UX porting tricks" maintained by
 * system@alchemy.chem.utoronto.ca (System Admin (Mike Peterson))
 * from the version "last updated: 11-Jan-1993"
 * Snarfage done by Jarkko Hietaniemi <Jarkko.Hietaniemi@hut.fi>
 * *) well, almost, had to K&R the function entry, HPUX "cc"
 * does not grok ANSI function prototypes */

/*
 * flock (fd, operation)
 *
 * This routine performs some file locking like the BSD 'flock'
 * on the object described by the int file descriptor 'fd',
 * which must already be open.
 *
 * The operations that are available are:
 *
 * LOCK_SH  -  get a shared lock.
 * LOCK_EX  -  get an exclusive lock.
 * LOCK_NB  -  don't block (must be ORed with LOCK_SH or LOCK_EX).
 * LOCK_UN  -  release a lock.
 *
 * Return value: 0 if lock successful, -1 if failed.
 *
 * Note that whether the locks are enforced or advisory is
 * controlled by the presence or absence of the SETGID bit on
 * the executable.
 *
 * Note that there is no difference between shared and exclusive
 * locks, since the 'lockf' system call in SYSV doesn't make any
 * distinction.
 *
 * The file "<sys/file.h>" should be modified to contain the definitions
 * of the available operations, which must be added manually (see below
 * for the values).
 */
static int flock(int fd, int operation) {
	int i;

	switch (operation) {
	case LOCK_SH:		/* get a shared lock */
	case LOCK_EX:		/* get an exclusive lock */
		i = lockf (fd, F_LOCK, 0);
		break;

	case LOCK_SH|LOCK_NB:	/* get a non-blocking shared lock */
	case LOCK_EX|LOCK_NB:	/* get a non-blocking exclusive lock */
		i = lockf (fd, F_TLOCK, 0);
		if (i == -1)
			if ((errno == EAGAIN) || (errno == EACCES))
				errno = EWOULDBLOCK;
		break;

	case LOCK_UN:		/* unlock */
		i = lockf (fd, F_ULOCK, 0);
		break;

	default:		/* can't decipher operation */
		i = -1;
		errno = EINVAL;
		break;
	}

	return (i);
}
#endif


static const char *progname;

/* Meant to be used atexit(close_stdout); */
static inline void close_stdout(void) {
	if (0 != ferror(stdout) || 0 != fclose(stdout)) {
		warn("write error");
		_exit(EXIT_FAILURE);
	}

	if (0 != ferror(stderr) || 0 != fclose(stderr)) {
		warn("write error");
		_exit(EXIT_FAILURE);
	}
}

static void usage(void) {
	fprintf(stderr, "\
usage: %s [-suno] [-w secs] <file> <command> [<arguments>...]\n\
       %s [-suno] [-w secs] <file-descriptor-number>\n"
		, progname, progname);
	exit(EX_USAGE);
}

static bool timeout_expired = false;

static void timeout_handler(int /*@unused@*/ sig __attribute__((__unused__))) {
	timeout_expired = true;
}

int main(int argc, char *argv[]) {
	int type = LOCK_EX; // -su

	bool have_timeout = false; // -w
	double raw_timeval;
	struct itimerval timer, old_timer;
	struct sigaction sa, old_sa;

	int block = 0; // -n

	bool close_before_exec = false; // -o

	// lockfile+cmd vs fd
	const char *filename = NULL;
	char **cmd_argv = NULL;
	int fd = -1;

	// internal state
	int opt;
	int status = EX_OK;
	int open_flags = 0;

	progname = basename(argv[0]);

	if (0 != atexit(close_stdout))
		err(EX_OSERR, "Could not attach atexit handler");

	if (argc < 2)
		usage();

	memset(&timer, 0, sizeof timer);

	while (-1 != (opt = getopt(argc, argv, "+suonw:"))) {
		switch (opt) {
		case 's':
			type = LOCK_SH;
			break;
		case 'u':
			type = LOCK_UN;
			break;
		case 'o':
			close_before_exec = true;
			break;
		case 'n':
			block = LOCK_NB;
			break;
		case 'w':
			have_timeout = true;
			raw_timeval = strtod(optarg, NULL);
			if (0 >= raw_timeval)
				errx(EX_USAGE, "timeout must be greater than 0, was %f", raw_timeval);
			timer.it_value.tv_sec = (time_t) raw_timeval;
			timer.it_value.tv_usec = (suseconds_t) ((raw_timeval - timer.it_value.tv_sec) * 1000000);
			break;
		case '?':
		default:
			usage();
			// should not get here
			break;
		}
	}


	if (argc - 1 > optind) {
		// Run command with lockfile
		filename = argv[optind];
		cmd_argv = &argv[optind + 1];

		// some systems allow exclusive locks on read-only files
		if (LOCK_SH == type || 0 != access(filename, W_OK)) {
			open_flags = O_RDONLY | O_NOCTTY | O_CREAT;
		} else {
			open_flags = O_WRONLY | O_NOCTTY | O_CREAT;
		}

		fd = open(filename, open_flags, 0666);

		// directories don't like O_WRONLY (and sometimes O_CREAT)
		if (fd < 0 && EISDIR == errno) {
			open_flags = O_RDONLY | O_NOCTTY;
			fd = open(filename, open_flags);
		}
		
		if (fd < 0) {
			warn("cannot open lock file %s", filename);
			switch (errno) {
			case ENOMEM:
			case EMFILE:
			case ENFILE:
				err(EX_OSERR, "OS error");
			case EROFS:
			case ENOSPC:
				err(EX_CANTCREAT, "could not create file");
			default:
				err(EX_NOINPUT, "invalid input");
			}
		}
	} else if (argc > optind) {
		// Use provided file descriptor
		fd = (int)strtol(argv[optind], NULL, 10);
	} else {
		// not enough parameters
		errx(EX_USAGE, "requires a file path, directory path, or file descriptor");
	}

	if (have_timeout) {
		memset(&sa, 0, sizeof sa);
		sa.sa_handler = timeout_handler;
		sa.sa_flags = SA_RESETHAND;
		if (0 != sigaction(SIGALRM, &sa, &old_sa))
				err(EX_OSERR, "could not attach timeout handler");
		if (0 != setitimer(ITIMER_REAL, &timer, &old_timer))
				err(EX_OSERR, "could not set interval timer");
	}

	while (0 != flock(fd, type | block)) {
		switch (errno) {
		case EWOULDBLOCK: // non-blocking lock not available
			exit(EXIT_FAILURE);
		case EISDIR: // interrupted by signal
			if (!timeout_expired) // failed to aquire lock in time
				exit(EXIT_FAILURE);
			continue;
		case EIO:
		case ENOLCK:
			err(EX_OSERR, "OS error");
		default:
			err(EX_DATAERR, "data error");
		}
	}

	if (have_timeout) {
		if (0 != setitimer(ITIMER_REAL, &old_timer, NULL))
				err(EX_OSERR, "could not reset old interval timer");
		if (0 != sigaction(SIGALRM, &old_sa, NULL))
				err(EX_OSERR, "could not reattach old timeout handler");
	}

	if (cmd_argv) {
		pid_t w, f;
		// Clear any inheirited settings
		signal(SIGCHLD, SIG_DFL);
		f = fork();

		if (f < 0) {
			err(EX_OSERR, "fork failed");
		} else if (0 == f) {
			if (close_before_exec)
				if (0 != close(fd))
					err(EX_OSERR, "could not close file descriptor");

			if (0 != execvp(cmd_argv[0], cmd_argv)) {
				warn("failed to execute command: %s", cmd_argv[0]);
				switch(errno) {
				case EIO:
				case ENOMEM:
					_exit(EX_OSERR);
				default:
					_exit(EX_NOINPUT);
				}
			}
		} else {
			do {
				w = waitpid(f, &status, 0);
				if (-1 == w && errno != EINTR)
					break;
			} while (w != f);

			if (-1 == w)
				err(EXIT_FAILURE, "waidpid failed");
			else if (0 != WIFEXITED(status))
				status = WEXITSTATUS(status);
			else if (0 != WIFSIGNALED(status))
				status = WTERMSIG(status) + 128;
			else
				status = EX_OSERR;
		}
	}

	return status;
}

