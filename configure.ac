AC_INIT([flock],
	[0.1.0],
	[joseph@josephholsten.com],,
	[https://github.com/josephholsten/flock])

AC_PREREQ([2.69])

AC_CONFIG_AUX_DIR([config])
AC_CONFIG_MACRO_DIR([m4])
dnl AC_USE_SYSTEM_EXTENSIONS must be called before any macros that run
dnl the compiler (like AC_PROG_LIBTOOL) to avoid autoconf errors.
AC_USE_SYSTEM_EXTENSIONS
AM_INIT_AUTOMAKE([-Wall -Wno-portability foreign 1.14 tar-pax no-dist-gzip dist-xz subdir-objects])
AM_SILENT_RULES([yes])
AC_CONFIG_SRCDIR([flock.c])

AC_PROG_CC_STDC
AC_CANONICAL_HOST
AC_C_CONST
AC_C_VOLATILE
AC_C_BIGENDIAN

AC_CHECK_HEADERS([ \
	err.h \
	errno.h \
	fcntl.h \
	locale.h \
	signal.h \
	stdio.h \
	stdlib.h \
	string.h \
	sys/time.h \
	sysexits.h \
	unistd.h \
])

AC_CHECK_FUNCS([ \
	err \
	errx \
	warn \
	warnx \
	flock \
])

LIBS=""

AC_CONFIG_HEADERS([config.h])

AC_CONFIG_FILES([
	Makefile \
])

AC_OUTPUT
