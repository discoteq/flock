#!/usr/bin/env bats
# The following seem to fail on systems without a native flock()

BASE=`dirname $BATS_TEST_DIRNAME`
FLOCK="${GRIND} ${BASE}/flock" # valgrind if you're so inclined
TIME=`which time` # don't use built-in time so we can access output
LOCKFILE=`mktemp -t flock.XXXXXXXXXX`

# -n fails immediately if file is locked
# 8
# fails "flock: data error: Bad file number"
@test "-n succeeds if lock is absent" {
        rm -f ${LOCKFILE}
        result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
        [ "$result" = run ]
}

# -u forcebly releases lock
# 10
# fails - does not release lock
@test "-u unlocks existing shared lock" {
        ${FLOCK} -s ${LOCKFILE} sleep 0.10 &
        ${FLOCK} -u ${LOCKFILE} true
        result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
        [ "$result" = err ]
}

# special file types

# 12
# fails "flock: data error: Bad file number"
@test "lock on non-existing file" {
        rm -f ${LOCKFILE}
        ${FLOCK} ${LOCKFILE} sleep 0.05 &
        result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
        [ "$result" = 0.05 ]
}

# 15
# fails "flock: data error: Bad file number"
@test "lock on dir" {
        rm -f ${LOCKFILE}
        mkdir -p ${LOCKFILE}
        ${FLOCK} ${LOCKFILE} sleep 0.05 &
        result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
        rm -rf  ${LOCKFILE}
        [ "$result" = 0.05 ]
}
