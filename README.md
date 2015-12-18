flock(1)
=======

[flock(1)](man/flock.1.md) locks files

## The simplest thing that could possibly work

To exclusively lock `/tmp/my.lock` while running the utility
`echo "hello, world!"`:

    flock /tmp/my.lock echo "hello, world!"

## Installing

Mac OS X Homebrew:

    brew tap discoteq/discoteq
    brew install flock

From source:

    FLOCK_VERSION=0.2.3
    wget https://github.com/discoteq/flock/releases/download/v${FLOCK_VERSION}/flock-${FLOCK_VERSION}.tar.xz
    xz -dc flock-${FLOCK_VERSION}.tar.xz | tar -x
    cd flock-${FLOCK_VERSION}
    ./configure
    make
    make install

## Wait, isn't there already a flock(1)?

Yep, it's part of [util-linux](https://en.wikipedia.org/wiki/Util-linux).

What makes discoteq flock(1) different is:

* Support for latest stable Linux (Debian & CentOS), Illumos (OmniOS & SmartOS), Darwin & FreeBSD
* Testing for all major features and edge conditions
* ISC license
* Public access to source history and bug tracking

## Project Principles

* Community: If a newbie has a bad time, it's a bug.
* Software: Make it work, then make it right, then make it fast.
* Technology: If it doesn't do a thing today, we can make it do it tomorrow.

## Contributing

Got an idea? Something smell wrong? Cause you pain? Or lost seconds of your life you'll never get back?

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members saying "send patches or die" - you will not see that here.

It is more important to me that you are able to contribute.

Creating a new [issue](https://github.com/discoteq/flock/issues) is probably the fastest way to get something fixed, but feel free to contact me via email (joseph@josephholsten.com), in IRC or however you can.

There's no wrong way to file a bug report, but I'll be able to help fastest if you can describe:
* what you did
* what you expected to happen
* what actually happened

(Some of the above was repurposed with <3 from logstash)
