#include <config.h>

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

#ifdef HAVE_SYS_FILE_H
#include <sys/file.h>
#endif

#ifndef HAVE_FLOCK
// lock operations for flock(2)
#define	LOCK_SH		0x01		// shared file lock
#define	LOCK_EX		0x02		// exclusive file lock
#define	LOCK_NB		0x04		// don't block when locking (must be ORed with LOCK_SH or LOCK_EX).
#define	LOCK_UN		0x08		// unlock file

/*
 * This function performs some file locking like the BSD 'flock'
 * on the object described by the int file descriptor 'fd',
 * which must already be open.
 *
 * Return value: 0 if lock successful, -1 if failed.
 *
 * Note that whether the locks are enforced or advisory is
 * controlled by the presence or absence of the SETGID bit on
 * the executable.
 */
static int flock(int fd, int operation) {
	struct flock fl;
	int cmd = F_SETLKW;
	int ret;

	// initialize the flock struct to set lock on entire file
	fl.l_whence = 0;
	fl.l_start = 0;
	fl.l_len = 0;
	fl.l_type = 0;

	// In non-blocking lock, use F_SETLK for cmd
	if (operation & LOCK_NB) {
		cmd = F_SETLK;
		operation &= ~LOCK_NB;  // turn off this bit
	}

	switch (operation) {
	case LOCK_UN:
		fl.l_type |= F_UNLCK;
		break;
	case LOCK_SH:
		fl.l_type |= F_RDLCK;
		break;
	case LOCK_EX:
		fl.l_type |= F_WRLCK;
		break;
	default:
		errno = EINVAL;
		return -1;
	}

	ret = fcntl(fd, cmd, &fl);

	if (ret == -1 && errno == EACCES)
		errno = EWOULDBLOCK;

	return ret;
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

