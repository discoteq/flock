#!/usr/bin/env bats

BASE=`dirname $BATS_TEST_DIRNAME`
FLOCK="${GRIND} ${BASE}/flock" # valgrind if you're so inclined
TIME=`which time` # don't use built-in time so we can access output

setup() {
	LOCKFILE=`mktemp -t flock.XXXXXXXXXX`
}

teardown() {
	jobs -p | xargs kill 2>/dev/null || true
	wait 2>/dev/null || true
	rm -rf ${LOCKFILE} 2>/dev/null || true
}

# Helper: check whether a command was blocked (waited) or ran immediately.
# Uses awk to compare elapsed time against a threshold.
was_blocked() {
	local elapsed="$1"
	# "blocked" means elapsed >= 0.3 seconds
	awk "BEGIN { exit ($elapsed >= 0.3) ? 0 : 1 }"
}

was_immediate() {
	local elapsed="$1"
	# "immediate" means elapsed < 0.3 seconds
	awk "BEGIN { exit ($elapsed < 0.3) ? 0 : 1 }"
}

# Hold a lock in the background and poll until it's actually acquired
hold_lock() {
	local flags="${1:-}"
	${FLOCK} ${flags} ${LOCKFILE} sleep 2 &
	local i=0
	while [ $i -lt 50 ]; do
		if ! ${FLOCK} -n ${LOCKFILE} true 2>/dev/null; then
			return 0
		fi
		sleep 0.05
		i=$((i + 1))
	done
	echo "hold_lock: timed out waiting for lock acquisition" >&2
	return 1
}

# Poll until an exclusive lock on LOCKFILE is held (nonblock probe fails)
wait_for_lock() {
	local i=0
	while [ $i -lt 50 ]; do
		if ! ${FLOCK} -n ${LOCKFILE} true 2>/dev/null; then
			return 0
		fi
		sleep 0.05
		i=$((i + 1))
	done
	echo "wait_for_lock: timed out" >&2
	return 1
}

get_elapsed() {
	${TIME} -p "$@" 2>&1 | awk '/real/ {print $2}'
}

###############################################################################
# Usage and help
###############################################################################

@test "no arguments prints usage to stderr and exits non-zero" {
	run ${FLOCK}
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage"* ]]
}

@test "-h exits with status 0 and prints usage to stdout" {
	run ${FLOCK} -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage"* ]]
	[[ "$output" == *"--shared"* ]]
}

@test "--help exits with status 0" {
	run ${FLOCK} --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage"* ]]
}

@test "-V prints version and exits 0" {
	run ${FLOCK} -V
	[ "$status" -eq 0 ]
	[[ "$output" == *"flock"* ]]
}

@test "--version prints version and exits 0" {
	run ${FLOCK} --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"flock"* ]]
}

@test "unknown option prints usage and exits non-zero" {
	run ${FLOCK} --bogus-option
	[ "$status" -ne 0 ]
}

###############################################################################
# Exclusive lock (default)
###############################################################################

@test "default lock is exclusive and blocks other exclusive locks" {
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "-x behaves as exclusive" {
	hold_lock "-x"
	result=$(get_elapsed ${FLOCK} -x ${LOCKFILE} true)
	was_blocked "$result"
}

@test "-e behaves as exclusive (alias for -x)" {
	hold_lock "-e"
	result=$(get_elapsed ${FLOCK} -e ${LOCKFILE} true)
	was_blocked "$result"
}

@test "--exclusive behaves as exclusive" {
	hold_lock "--exclusive"
	result=$(get_elapsed ${FLOCK} --exclusive ${LOCKFILE} true)
	was_blocked "$result"
}

@test "exclusive lock blocks shared lock" {
	hold_lock
	result=$(get_elapsed ${FLOCK} -s ${LOCKFILE} true)
	was_blocked "$result"
}

###############################################################################
# Shared lock (-s, --shared)
###############################################################################

@test "-s allows other shared locks" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} -s ${LOCKFILE} true)
	was_immediate "$result"
}

@test "-s prevents exclusive locks" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "--shared allows other shared locks" {
	hold_lock "--shared"
	result=$(get_elapsed ${FLOCK} --shared ${LOCKFILE} true)
	was_immediate "$result"
}

@test "--shared prevents exclusive locks" {
	hold_lock "--shared"
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "multiple shared locks can coexist" {
	${FLOCK} -s ${LOCKFILE} sleep 2 &
	${FLOCK} -s ${LOCKFILE} sleep 2 &
	sleep 0.2  # shared locks don't block nonblock probe, just wait briefly
	# A third shared lock should also be immediate
	result=$(get_elapsed ${FLOCK} -s ${LOCKFILE} true)
	was_immediate "$result"
}

###############################################################################
# Nonblock (-n, --nonblock, --nb)
###############################################################################

@test "-n fails immediately if exclusive lock exists" {
	hold_lock
	run ${FLOCK} -n ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "-n fails immediately if shared lock exists" {
	hold_lock "-s"
	run ${FLOCK} -n ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "-n succeeds if no lock exists" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} -n ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "-n shared succeeds when shared lock is held" {
	hold_lock "-s"
	result=$(${FLOCK} -n -s ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "-n shared fails when exclusive lock is held" {
	hold_lock
	run ${FLOCK} -n -s ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "--nonblock fails if exclusive lock exists" {
	hold_lock
	run ${FLOCK} --nonblock ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "--nonblock succeeds if lock is absent" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} --nonblock ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "--nb is an alias for --nonblock" {
	hold_lock
	run ${FLOCK} --nb ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

###############################################################################
# Timeout (-w, --timeout, --wait)
###############################################################################

@test "-w succeeds if lock is released before timeout" {
	${FLOCK} ${LOCKFILE} sleep 0.3 &
	sleep 0.1
	result=$(${FLOCK} -w 3 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

@test "-w fails if lock isn't released in time" {
	hold_lock
	result=$(${FLOCK} -w 0.1 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

@test "-w fails for zero timeout" {
	hold_lock
	result=$(${FLOCK} -w 0.0 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

@test "-w with fractional seconds works" {
	${FLOCK} ${LOCKFILE} sleep 0.2 &
	sleep 0.1
	result=$(${FLOCK} -w 1.5 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

@test "--timeout succeeds if lock is released before timeout" {
	${FLOCK} ${LOCKFILE} sleep 0.3 &
	sleep 0.1
	result=$(${FLOCK} --timeout 3 ${LOCKFILE} echo run || echo err)
	[ "$result" = run ]
}

@test "--timeout fails if lock isn't released in time" {
	hold_lock
	result=$(${FLOCK} --timeout 0.1 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

@test "--wait is an alias for --timeout" {
	hold_lock
	result=$(${FLOCK} --wait 0.1 ${LOCKFILE} echo run || echo err)
	[ "$result" = err ]
}

@test "-w without contention succeeds immediately" {
	rm -f ${LOCKFILE}
	result=$(${FLOCK} -w 1 ${LOCKFILE} echo run)
	[ "$result" = run ]
}

###############################################################################
# Conflict exit code (-E, --conflict-exit-code)
###############################################################################

@test "-E sets custom exit code for -n conflict" {
	hold_lock
	run ${FLOCK} -n -E 42 ${LOCKFILE} echo run
	[ "$status" -eq 42 ]
}

@test "-E sets custom exit code for -w timeout" {
	hold_lock
	run ${FLOCK} -w 0.1 -E 99 ${LOCKFILE} echo run
	[ "$status" -eq 99 ]
}

@test "--conflict-exit-code works as long form" {
	hold_lock
	run ${FLOCK} -n --conflict-exit-code 77 ${LOCKFILE} echo run
	[ "$status" -eq 77 ]
}

@test "-E 0 makes conflict look like success" {
	hold_lock
	run ${FLOCK} -n -E 0 ${LOCKFILE} echo run
	[ "$status" -eq 0 ]
}

@test "-E rejects empty string" {
	run ${FLOCK} -n -E "" ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "-E rejects non-numeric argument" {
	run ${FLOCK} -n -E foo ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
	[[ "$output" == *"conflict exit code"* ]]
}

@test "-E rejects negative value" {
	run ${FLOCK} -n -E -1 ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "-E rejects value above 255" {
	run ${FLOCK} -n -E 256 ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
	[[ "$output" == *"conflict exit code"* ]]
}

@test "-E rejects overflow value" {
	run ${FLOCK} -n -E 99999999999999999999 ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
	[[ "$output" == *"conflict exit code"* ]]
}

###############################################################################
# Unlock (-u, --unlock)
###############################################################################

@test "-u unlocks existing exclusive lock" {
	hold_lock
	result=$(get_elapsed ${FLOCK} -u ${LOCKFILE} true)
	was_immediate "$result"
}

@test "-u unlocks existing shared lock" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} -u ${LOCKFILE} true)
	was_immediate "$result"
}

@test "--unlock unlocks existing exclusive lock" {
	hold_lock
	result=$(get_elapsed ${FLOCK} --unlock ${LOCKFILE} true)
	was_immediate "$result"
}

@test "--unlock unlocks existing shared lock" {
	hold_lock "-s"
	result=$(get_elapsed ${FLOCK} --unlock ${LOCKFILE} true)
	was_immediate "$result"
}

###############################################################################
# Command execution (-c, --command)
###############################################################################

@test "-c runs command through shell" {
	result=$(${FLOCK} ${LOCKFILE} -c "echo run")
	[ "$result" = run ]
}

@test "--command runs command through shell" {
	result=$(${FLOCK} ${LOCKFILE} --command "echo run")
	[ "$result" = run ]
}

@test "-c supports shell features (pipes)" {
	result=$(${FLOCK} ${LOCKFILE} -c "echo hello | tr h H")
	[ "$result" = Hello ]
}

@test "-c supports shell features (variable expansion)" {
	result=$(${FLOCK} ${LOCKFILE} -c 'echo $((2 + 3))')
	[ "$result" = 5 ]
}

@test "-c supports shell features (command substitution)" {
	result=$(${FLOCK} ${LOCKFILE} -c 'echo $(echo nested)')
	[ "$result" = nested ]
}

@test "-c requires exactly one argument" {
	run ${FLOCK} ${LOCKFILE} -c echo extra args
	[ "$status" -ne 0 ]
}

@test "-c must come after lockfile" {
	run ${FLOCK} -c "echo 1" ${LOCKFILE}
	[ "$status" -ne 0 ]
}

###############################################################################
# Child exit status propagation
###############################################################################

@test "child exit 0 propagates to flock exit 0" {
	run ${FLOCK} ${LOCKFILE} true
	[ "$status" -eq 0 ]
}

@test "child exit 1 propagates to flock exit 1" {
	run ${FLOCK} ${LOCKFILE} false
	[ "$status" -eq 1 ]
}

@test "child custom exit code propagates" {
	run ${FLOCK} ${LOCKFILE} sh -c "exit 42"
	[ "$status" -eq 42 ]
}

@test "child exit 255 propagates" {
	run ${FLOCK} ${LOCKFILE} sh -c "exit 255"
	[ "$status" -eq 255 ]
}

@test "nonexistent command returns non-zero" {
	run ${FLOCK} ${LOCKFILE} /nonexistent/command/that/does/not/exist
	[ "$status" -ne 0 ]
}

@test "-c child exit code propagates" {
	run ${FLOCK} ${LOCKFILE} -c "exit 7"
	[ "$status" -eq 7 ]
}

###############################################################################
# Lock file types
###############################################################################

@test "lock on existing file" {
	touch ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock creates non-existing file" {
	rm -f ${LOCKFILE}
	${FLOCK} ${LOCKFILE} true
	[ -f ${LOCKFILE} ]
}

@test "lock on non-existing file blocks correctly" {
	rm -f ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 2 &
	wait_for_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on read-only file" {
	touch ${LOCKFILE}
	chmod 444 ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on write-only file" {
	touch ${LOCKFILE}
	chmod 222 ${LOCKFILE}
	hold_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on directory" {
	rm -f ${LOCKFILE}
	mkdir -p ${LOCKFILE}
	${FLOCK} ${LOCKFILE} sleep 2 &
	wait_for_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock on file with spaces in path" {
	local SPACEFILE="${LOCKFILE} with spaces"
	touch "${SPACEFILE}"
	${FLOCK} "${SPACEFILE}" sleep 2 &
	local i=0
	while [ $i -lt 50 ]; do
		if ! ${FLOCK} -n "${SPACEFILE}" true 2>/dev/null; then break; fi
		sleep 0.05; i=$((i + 1))
	done
	result=$(get_elapsed ${FLOCK} "${SPACEFILE}" true)
	rm -f "${SPACEFILE}"
	was_blocked "$result"
}

@test "lock file in non-existent directory fails" {
	run ${FLOCK} /nonexistent/dir/lockfile true
	[ "$status" -ne 0 ]
}

###############################################################################
# File descriptor mode
###############################################################################

@test "lock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		sleep 2
	) 8> ${LOCKFILE} &
	wait_for_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_blocked "$result"
}

@test "lock then unlock on file descriptor" {
	(
		${FLOCK} -n 8 || exit 1
		sleep 1
		${FLOCK} -u 8 || exit 1
		sleep 5
	) 8> ${LOCKFILE} &
	wait_for_lock
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	# Should be blocked for ~1s (until unlock), not ~6s (until subshell exit)
	was_blocked "$result"
	# Upper bound: must complete well before the holder exits at ~6s
	awk "BEGIN { exit ($result < 4.0) ? 0 : 1 }"
}

@test "shared lock on file descriptor" {
	(
		${FLOCK} -s 8 || exit 1
		sleep 2
	) 8> ${LOCKFILE} &
	sleep 0.2  # shared lock doesn't block nonblock probe, just wait briefly
	# Another shared lock should be immediate
	result=$(get_elapsed ${FLOCK} -s ${LOCKFILE} true)
	was_immediate "$result"
}

@test "fd mode nonblock fails when fd is locked" {
	(
		${FLOCK} -n 8 || exit 1
		sleep 2
	) 8> ${LOCKFILE} &
	wait_for_lock
	run ${FLOCK} -n ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "fd mode rejects empty string" {
	run ${FLOCK} ""
	[ "$status" -ne 0 ]
}

@test "fd mode rejects non-numeric argument" {
	run ${FLOCK} abc
	[ "$status" -ne 0 ]
	[[ "$output" == *"bad file descriptor"* ]]
}

@test "fd mode rejects negative fd" {
	run ${FLOCK} -- -1
	[ "$status" -ne 0 ]
	[[ "$output" == *"bad file descriptor"* ]]
}

@test "fd mode rejects overflow fd" {
	run ${FLOCK} 99999999999999999999
	[ "$status" -ne 0 ]
	[[ "$output" == *"bad file descriptor"* ]]
}

###############################################################################
# Close-before-exec (-o, --close)
###############################################################################

@test "-o runs command successfully" {
	result=$(${FLOCK} -o ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "--close runs command successfully" {
	result=$(${FLOCK} --close ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "-o closes fd before exec so grandchildren don't inherit lock" {
	# Without -o, a grandchild inherits the lock fd and holds the lock
	# until it exits. With -o, the fd is closed before exec, so grandchild
	# processes don't inherit it.
	# Spawn a grandchild that outlives the flock parent, then verify
	# another process can acquire the lock while the grandchild is alive.
	${FLOCK} -o ${LOCKFILE} sh -c "sleep 5 &" &
	FLOCK_PID=$!
	wait $FLOCK_PID
	# The grandchild (sleep 5) is still running but shouldn't hold the lock
	run ${FLOCK} -n ${LOCKFILE} echo relocked
	[ "$status" -eq 0 ]
	[ "$output" = relocked ]
}

###############################################################################
# Verbose (--verbose)
###############################################################################

@test "--verbose produces lock acquisition and timing output" {
	result=$(${FLOCK} --verbose ${LOCKFILE} true 2>&1)
	[[ "$result" == *"getting lock"* ]]
	[[ "$result" == *"microseconds"* ]]
}

@test "--verbose in fd mode reports sane timing" {
	# Regression: t_l_req was uninitialized in FD mode, producing
	# garbage like "took 1774858164251193 microseconds"
	result=$( (${FLOCK} --verbose 8) 8> ${LOCKFILE} 2>&1 )
	[[ "$result" == *"microseconds"* ]]
	# Extract the number and verify it's under 1 second (1000000 us)
	elapsed=$(echo "$result" | grep -o '[0-9]* microseconds' | grep -o '[0-9]*')
	[ "$elapsed" -lt 1000000 ]
}

###############################################################################
# Lock is released when holder exits
###############################################################################

@test "lock is released when holder process exits" {
	${FLOCK} ${LOCKFILE} sleep 0.3 &
	sleep 0.1
	# Wait for the holder to finish
	wait
	# Now the lock should be free
	result=$(get_elapsed ${FLOCK} ${LOCKFILE} true)
	was_immediate "$result"
}

###############################################################################
# Option combinations
###############################################################################

@test "-x -n combined: exclusive nonblock" {
	hold_lock
	run ${FLOCK} -x -n ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "-s -n combined: shared nonblock succeeds with shared held" {
	hold_lock "-s"
	result=$(${FLOCK} -s -n ${LOCKFILE} echo run)
	[ "$result" = run ]
}

@test "-s -n combined: shared nonblock fails with exclusive held" {
	hold_lock
	run ${FLOCK} -s -n ${LOCKFILE} echo run
	[ "$status" -ne 0 ]
}

@test "last lock type flag wins (-s then -x)" {
	hold_lock "-s"
	# -s then -x: should try exclusive, which should block on shared
	result=$(get_elapsed ${FLOCK} -s -x ${LOCKFILE} true)
	was_blocked "$result"
}

@test "last lock type flag wins (-x then -s)" {
	hold_lock "-s"
	# -x then -s: should try shared, which should be immediate with shared held
	result=$(get_elapsed ${FLOCK} -x -s ${LOCKFILE} true)
	was_immediate "$result"
}

@test "-w with -E sets timeout exit code" {
	hold_lock
	run ${FLOCK} -w 0.1 -E 55 ${LOCKFILE} echo run
	[ "$status" -eq 55 ]
}

@test "-n with -E 0 exits 0 on conflict" {
	hold_lock
	run ${FLOCK} -n -E 0 ${LOCKFILE} echo run
	[ "$status" -eq 0 ]
	# But the command should NOT have run
	[[ "$output" != *"run"* ]]
}
