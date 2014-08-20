#!/usr/bin/env bats

BASE=`dirname $BATS_TEST_DIRNAME`
FLOCK="${GRIND} ${BASE}/flock" # valgrind if you're so inclined
TIME=`which time` # don't use built-in time so we can access output
LOCKFILE=`mktemp -t flock.XXXXXXXXXX`

# default uses an exclusive lock
@test "exclusive lock prevents addl exclusive locks" {
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

# -s uses a shared lock instead of exclusive
@test "-s allows other shared locks" {
	${FLOCK} -s ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} -s ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.00 ]
}
@test "-s prevents exclusive locks" {
	${FLOCK} -s ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

# -o doesn't pass fd to child, how to test?

# -w sec waits for file to become unlocked, failing after timeout
@test "-w runs command if the lock is released" {
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${FLOCK} -w 0.10 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}
@test "-w fails if the lock isn't released in time" {
	${FLOCK} ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -w 0.05 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-w fails for zero time" {
	${FLOCK} ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -w 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-w fails for negative time" {
	${FLOCK} ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -w 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

# -n fails immediately if file is locked
@test "-n fails if exclusive lock exists" {
	${FLOCK} ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-n fails if shared lock exists" {
	${FLOCK} -s ${LOCKFILE} sleep 0.10 &
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}
@test "-n succeeds if lock is absent" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} -n ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

# -u forcebly releases lock
@test "-u unlocks existing exclusive lock" {
	${FLOCK} ${LOCKFILE} sleep 0.10 &
	result=$(${TIME} -p ${FLOCK} -u ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.00 ]
}
@test "-u unlocks existing shared lock" {
	${FLOCK} -s ${LOCKFILE} sleep 0.10 &
	result=$(${TIME} -p ${FLOCK} -u ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.00 ]
}

# special file types
@test "lock on existing file" {
	touch ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

@test "lock on non-existing file" {
	rm -f ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

@test "lock on read-only file" {
	touch ${LOCKFILE}
	chmod 444 ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	rm -f ${LOCKFILE}
	[ "$result" = 0.05 ]
}

@test "lock on write-only file" {
	touch ${LOCKFILE}
	chmod 222 ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	rm -f ${LOCKFILE}
	[ "$result" = 0.05 ]
}

@test "lock on dir" {
	rm -f ${LOCKFILE}
	mkdir -p ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 0.05 &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	rm -rf  ${LOCKFILE}
	[ "$result" = 0.05 ]
}

# fd mode
@test "lock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		# commands executed under lock ...
		sleep 0.05
	) 8> ${LOCKFILE} &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}

@test "lock, then unlock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		# commands executed under lock ...
		sleep 0.05
		${FLOCK} -u 8 || exit 1
		sleep 0.05
	) 8> ${LOCKFILE} &
	result=$(${TIME} -p ${FLOCK} ${LOCKFILE} true 2>&1 | awk '/real/ {print $2}')
	[ "$result" = 0.05 ]
}
