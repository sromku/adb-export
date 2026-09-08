#!/usr/bin/env bash
# Test suite for adb-export.sh. Uses test/fake-adb instead of a real device.
#
#   ./test/run.sh            run with the bash on PATH
#   bash3 ./test/run.sh      run with a specific bash
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../adb-export.sh"
FIXTURES="$HERE/fixtures"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/adb-export-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

export ADB="$HERE/fake-adb"
export FAKE_ADB_LOG="$WORK/adb.log"
unset ANDROID_SERIAL

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /'; }

# run <name> <expected-exit> <fixture> [args...]
# Runs the script with the given fixture, checks the exit code, and leaves the
# output in $OUT, stderr in $ERR and the export directory (if any) in $EXPORT.
run() {
	local name=$1 expected=$2 fixture=$3; shift 3
	local rc=0
	rm -rf "$WORK/out"
	: > "$FAKE_ADB_LOG"
	OUT=$(FAKE_ADB_FIXTURE="$FIXTURES/$fixture" bash "$SCRIPT" -o "$WORK/out" "$@" 2> "$WORK/stderr") || rc=$?
	ERR=$(cat "$WORK/stderr")
	EXPORT=$(find "$WORK/out" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
	if [ "$rc" -eq "$expected" ]; then
		ok "$name: exit code $rc"
	else
		fail "$name: expected exit code $expected, got $rc" "$ERR"
	fi
}

# csv_is <name> <expected-file>
csv_is() {
	local name=$1 expected=$2 diff_out
	if diff_out=$(diff "$expected" "$EXPORT/data.csv" 2>&1); then
		ok "$name: CSV matches $(basename "$expected")"
	else
		fail "$name: CSV differs from $(basename "$expected")" "$diff_out"
	fi
}

# check <name> <command...>  passes when the command succeeds
check() {
	local name=$1; shift
	if "$@"; then ok "$name"; else fail "$name"; fi
}

# matches <name> <haystack> <extended-regex>  passes when a line matches
matches() {
	if printf '%s\n' "$2" | grep -qE "$3"; then ok "$1"; else fail "$1: no line matches '$3' in:" "$2"; fi
}

# contains <name> <haystack> <needle>
contains() {
	case "$2" in
		*"$3"*) ok "$1" ;;
		*) fail "$1: expected to find '$3' in:" "$2" ;;
	esac
}

# ------------------------------------------------------------- parsing ---

run "basic" 0 basic.txt content://settings/global
csv_is "basic" "$FIXTURES/basic.csv"
contains "basic: raw output kept" "$(ls "$EXPORT")" "raw_query.txt"
contains "basic: export dir named after the uri" "$EXPORT" "/settings_global-"
contains "basic: summary lists columns" "$ERR" "Columns (4): _id, name, value, is_preserved_in_restore"
contains "basic: summary counts rows" "$ERR" "Rows exported: 3"

run "crlf" 0 crlf.txt content://settings/global
csv_is "crlf" "$FIXTURES/basic.csv"

run "tricky" 0 tricky.txt content://com.example/things
csv_is "tricky" "$FIXTURES/tricky.csv"
contains "tricky: summary counts rows" "$ERR" "Rows exported: 8"

run "stdout" 0 tricky.txt -c content://com.example/things
if [ "$OUT" = "$(cat "$FIXTURES/tricky.csv")" ]; then ok "stdout: CSV on stdout"; else fail "stdout: CSV differs" "$OUT"; fi
check "stdout: no export dir created" [ -z "$EXPORT" ]

run "empty" 0 empty.txt content://user_dictionary/words
contains "empty: message" "$ERR" "no rows"
check "empty: data.csv exists" [ -f "$EXPORT/data.csv" ]
check "empty: data.csv is empty" [ ! -s "$EXPORT/data.csv" ]

run "provider error" 1 error.txt content://does.not.exist/foo
contains "provider error: message shown" "$ERR" "Could not find provider: does.not.exist"
check "provider error: no CSV written" [ ! -e "$EXPORT/data.csv" ]
check "provider error: raw output kept" [ -s "$EXPORT/raw_query.txt" ]

run "permission error" 1 permission.txt content://sms
contains "permission error: message shown" "$ERR" "requires android.permission.READ_SMS"

# ----------------------------------------------------------- arguments ---

run "legacy -e" 0 basic.txt -e content://settings/global
csv_is "legacy -e" "$FIXTURES/basic.csv"

run "query options" 0 basic.txt content://settings/global -u 0 -p name:value -w "name='it''s'" --sort "name ASC"
contains "query options: remote command quoted" "$(cat "$FAKE_ADB_LOG")" \
	"content query --uri 'content://settings/global' --user '0' --projection 'name:value' --where 'name='\''it'\'''\''s'\''' --sort 'name ASC'"

run "no uri" 1 basic.txt
contains "no uri: usage shown" "$ERR" "Usage:"

run "bad uri" 1 basic.txt http://example.com
contains "bad uri: message" "$ERR" "should start with content://"

run "unknown option" 1 basic.txt --bogus content://settings/global
contains "unknown option: message" "$ERR" "unknown option: --bogus"

run "missing option value" 1 basic.txt content://settings/global -s
contains "missing option value: message" "$ERR" "requires an argument"

run "help" 0 basic.txt --help
contains "help: usage shown" "$OUT" "Usage:"

run "version" 0 basic.txt --version
contains "version: printed" "$OUT" "."

# --------------------------------------------------------------- probe ---

run "probe rows" 0 basic.txt --probe
contains "probe rows: header" "$OUT" "Probing 62 content URIs on emulator-5554"
contains "probe rows: section title" "$OUT" "Calendar"
matches "probe rows: verdict line" "$OUT" "^  rows +3  content://settings/global$"
contains "probe rows: summary" "$OUT" "rows: 62  empty: 0  denied: 0  missing: 0  error: 0"
check "probe rows: no export dir created" [ -z "$EXPORT" ]

run "probe custom list" 0 empty.txt --probe content://a/b content://c/d
contains "probe custom list: header" "$OUT" "Probing 2 content URIs"
matches "probe custom list: empty verdict" "$OUT" "^  empty +content://a/b$"
contains "probe custom list: summary" "$OUT" "rows: 0  empty: 2  denied: 0  missing: 0  error: 0"
contains "probe custom list: remote command" "$(cat "$FAKE_ADB_LOG")" "content query --uri 'content://c/d'"

run "probe missing" 0 error.txt --probe content://does.not.exist/foo
matches "probe missing: verdict" "$OUT" "^  missing +content://does.not.exist/foo  \\(Could not find provider: does.not.exist\\)$"

run "probe denied" 0 probe-denied.txt --probe content://telephony/siminfo
matches "probe denied: verdict" "$OUT" "^  denied +content://telephony/siminfo  \\(Access SIMINFO table from not phone/system UID\\)$"

run "probe bad uri" 1 basic.txt --probe content://a/b http://nope
contains "probe bad uri: message" "$ERR" "should start with content://"

# ------------------------------------------------------------- devices ---

FAKE_ADB_DEVICES="" run "no device" 1 basic.txt content://settings/global
contains "no device: message" "$ERR" "no device found"

FAKE_ADB_DEVICES='emulator-5554\tdevice\nABC123\tdevice' run "two devices" 1 basic.txt content://settings/global
contains "two devices: asks for -s" "$ERR" "pick one with -s <serial>, e.g. -s emulator-5554"
contains "two devices: lists them" "$ERR" "ABC123"

FAKE_ADB_DEVICES='emulator-5564\toffline\nABC123\tdevice\nemulator-5566\toffline\nXYZ\tunauthorized' run "one ready among offline" 0 basic.txt content://settings/global
contains "one ready among offline: picks the ready device" "$ERR" "from ABC123"

FAKE_ADB_DEVICES='emulator-5564\toffline\nemulator-5566\toffline' run "all offline" 1 basic.txt content://settings/global
contains "all offline: message" "$ERR" "no device is ready"
contains "all offline: lists them" "$ERR" "emulator-5566"

FAKE_ADB_DEVICES='emulator-5554\tdevice\nABC123\tdevice' run "two devices with -s" 0 basic.txt -s ABC123 content://settings/global
contains "two devices with -s: summary names device" "$ERR" "from ABC123"

FAKE_ADB_DEVICES='emulator-5554\tdevice\nABC123\tdevice' ANDROID_SERIAL=ABC123 run "ANDROID_SERIAL" 0 basic.txt content://settings/global
contains "ANDROID_SERIAL: summary names device" "$ERR" "from ABC123"

FAKE_ADB_DEVICES='ABC123\tunauthorized' run "unauthorized" 1 basic.txt content://settings/global
contains "unauthorized: message" "$ERR" "Accept the USB debugging prompt"

FAKE_ADB_DEVICES='ABC123\tdevice' run "wrong serial" 1 basic.txt -s NOPE content://settings/global
contains "wrong serial: message" "$ERR" "not connected"

# --------------------------------------------------------------- done ---

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
