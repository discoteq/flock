#!/usr/bin/env bats
# The following seem to fail on systems without a native flock()

BASE=`dirname $BATS_TEST_DIRNAME`
FLOCK="${GRIND} ${BASE}/flock" # valgrind if you're so inclined
TIME=`which time` # don't use built-in time so we can access output
LOCKFILE=`mktemp -t flock.XXXXXXXXXX`

# -s uses a shared lock instead of exclusive
# 3
@test "-s prevents exclusive locks" {
	${FLOCK} -s ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

# -n fails immediately if file is locked
# 7
@test "-n fails if shared lock exists" {
	${FLOCK} -s ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
# 8
@test "-n succeeds if lock is absent" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

# -u forcebly releases lock
# 10
@test "-u unlocks existing shared lock" {
	${FLOCK} -s ${LOCKFILE} sleep 0.10 &
	${FLOCK} -u ${LOCKFILE} true
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

# special file types

# 12
@test "lock on non-existing file" {
	rm -f ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

# 13
@test "lock on read-only file" {
	touch ${LOCKFILE}
	chmod 444 ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	rm -f ${LOCKFILE}
	[ "$result" = 0.05 ]
}

# 15
@test "lock on dir" {
	rm -f ${LOCKFILE}
	mkdir -p ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	rm -rf  ${LOCKFILE}
	[ "$result" = 0.05 ]
}

# fd mode
# 16
@test "lock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		# commands executed under lock ...
		sleep 0.05
	) 8> ${LOCKFILE} &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}


