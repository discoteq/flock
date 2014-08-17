#!/bin/sh
# you can either set the environment variables AUTOCONF, AUTOHEADER, AUTOMAKE,
# ACLOCAL, AUTOPOINT and/or LIBTOOLIZE to the right versions, or leave them
# unset and get the defaults

autoreconf --verbose --force --install --symlink --make -Wall || {
	echo 'autoreconf failed' 1>&2
	exit 1
}

./configure || {
	echo 'configure failed' 1>&2
	exit 1
}

echo
echo "Now type 'make' to compile this package."
echo
