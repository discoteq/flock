# you probably want one of the following tasks:
# - all
# - install
# - pkg
# - doc
# - test

# utilities
RONN=ronn
RONN_FLAGS=\
	--manual="User Commands" \
	--organization=dicoteq \
	--date=2014-07-17
OPEN=open
GIT=git
CPIO=cpio
LINT=splint
LINT_FLAGS=+posixlib

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

lint:
	$(LINT) $(LINT_FLAGS) src/flock.c

man_MANS = man/flock.1
man/flock.1: man/flock.1.md man/index.txt
	$(RONN) $(RONN_FLAGS) -r man/flock.1.md
man/flock.1.html: man/flock.1.md man/index.txt
	$(RONN) $(RONN_FLAGS) -5 man/flock.1.md
nroff-man: man/flock.1
	$(NROFF) -man < man/flock.1
html-man: man/flock.1.html
	$(OPEN) man/flock.1.html
doc: man/flock.1 man/flock.1.html

test: flock t/default.bats
	t/default.bats

PKGFILES=\
	LICENSE.md \
	Makefile.am \
	README.md \
	configure.ac \
	man/flock.1 \
	man/index.txt \
	src/flock.c \
	t/default.bats

pkg: flock.cpio
flock.cpio: $(PKGFILES)
	$(GIT) ls-files | $(CPIO) -o > flock.cpio
