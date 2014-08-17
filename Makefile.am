AM_CPPFLAGS = \
	-include config.h \
	-I$(top_srcdir)/include \
	-DLOCALEDIR=\"$(localedir)\" \
	-D_PATH_LOCALSTATEDIR=\"${localstatedir}\"

AM_CFLAGS = \
	-fsigned-char \
	-fno-common \
	-Wall \
	-Wextra \
	-Wpedantic \
	-Werror \
	-Wmissing-declarations \
	-Wmissing-prototypes \
	-Wredundant-decls \
	-Wtype-limits \
	-Wunused-parameter \
	-Wunused-result \
	-Wnested-externs \
	-Wpointer-arith \
	-Wstrict-prototypes \
	-Wformat=2

AM_LDFLAGS =

pkgconfigdir = $(usrlib_execdir)/pkgconfig

RCS_FIND_IGNORE = \( -o -name .git \) -prune -o

ACLOCAL_AMFLAGS = -I m4

# dist_noinst_HEADERS =
bin_PROGRAMS = flock
flock_SOURCES = src/flock.c
flock_LDADD = $(LDADD)

DISTCLEANFILES = \
	configure \
	Makefile.in \
	aclocal.m4 \
	config.h.in
distclean-local:
	-rm -rf autom4te.cache
	-rm -rf config
	-rm -rf m4

SPLINT_FLAGS=+posixlib
lint:
	splint $(SPLINT_FLAGS) src/flock.c

RONN=ronn
NROFF=nroff
OPEN=open
RONN_FLAGS=\
	--manual="User Commands" \
	--organization=dicoteq \
	--date=2014-07-17

man_MANS = man/flock.1
man/flock.1: man/flock.1.md man/index.txt
	$(RONN) $(RONN_FLAGS) -r man/flock.1.md
man/flock.1.html: man/flock.1.md man/index.txt
	$(RONN) $(RONN_FLAGS) -5 man/flock.1.md
nroff-man: man/flock.1
	$(NROFF) -man < man/flock.1
html-man: man/flock.1.html
	$(OPEN) man/flock.1.html

check-test:
	test/default.bats

PKGFILES=\
	man/flock.1 \
	man/index.txt \
	src/flock.c \
	Makefile.am \
	README \
	t/default.bats \
	configure.ac

GIT=git
CPIO=cpio
pkg: flock.cpio
flock.cpio: $(PKGFILES)
	$(GIT) ls-files | $(CPIO) -o > flock.cpio
