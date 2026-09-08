#!/usr/bin/env bash
#
# adb-export - export the rows of an Android content provider to CSV over adb.
#
# author:  Roman Kushnarenko @sromku
# license: Apache License 2.0
# repo:    https://github.com/sromku/adb-export
#
# Requirements: bash 3.2+, awk, adb (Android platform-tools), a device with
# USB debugging enabled.

set -euo pipefail

VERSION="2.0.0"

# ------------------------------------------------------------------ usage ---

usage() {
	cat <<EOF
adb-export $VERSION - export an Android content provider to CSV

Usage:
  adb-export.sh [options] <content-uri>
  adb-export.sh -e <content-uri> [options]
  adb-export.sh --probe [options] [content-uri...]

Options:
  -e, --uri <uri>          Content provider URI to export (content://...)
  -o, --out <dir>          Directory to create the export folder in
                           (default: ./exports)
  -c, --stdout             Write the CSV to stdout instead of files
  -s, --serial <serial>    Target device (see 'adb devices'); also honours
                           the ANDROID_SERIAL environment variable
  -u, --user <id>          Android user id to query as (content --user)
  -p, --projection <cols>  Colon separated column names, e.g. name:value
  -w, --where <clause>     SQL where clause, e.g. "name='foo'"
      --sort <order>       Sort order, e.g. "name ASC"
      --probe              Do not export; query a built-in list of well known
                           content URIs (or the URIs given on the command
                           line) and report which ones return rows, are
                           empty, are denied or do not exist on the device
  -q, --quiet              Only print errors
  -h, --help               Show this help
  -V, --version            Print the version

Environment:
  ADB                      Path to the adb binary. When unset, adb is looked
                           up on PATH and in the usual Android SDK locations.

Examples:
  adb-export.sh content://settings/global
  adb-export.sh -e content://com.android.contacts/contacts -o ~/Desktop
  adb-export.sh content://settings/secure -p name:value --sort "name ASC"
  adb-export.sh content://media/external/images/media --stdout > images.csv
  adb-export.sh --probe

A list of content URIs that are known to work is in the README:
  https://github.com/sromku/adb-export
EOF
}

# ------------------------------------------------------------ messaging ---

QUIET=false

info() { [ "$QUIET" = true ] || printf '%s\n' "$*" >&2; }
die()  { printf 'adb-export: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------ arguments ---

URI=""
PROBE=false
PROBE_URIS=""
OUT_DIR="./exports"
TO_STDOUT=false
SERIAL="${ANDROID_SERIAL:-}"
USER_ID=""
PROJECTION=""
WHERE=""
SORT=""

need_arg() {
	[ $# -ge 2 ] || die "option $1 requires an argument (see --help)"
}

while [ $# -gt 0 ]; do
	case "$1" in
		-e|--uri)        need_arg "$@"; URI=$2; shift 2 ;;
		-o|--out)        need_arg "$@"; OUT_DIR=$2; shift 2 ;;
		-c|--stdout)     TO_STDOUT=true; shift ;;
		-s|--serial)     need_arg "$@"; SERIAL=$2; shift 2 ;;
		-u|--user)       need_arg "$@"; USER_ID=$2; shift 2 ;;
		-p|--projection) need_arg "$@"; PROJECTION=$2; shift 2 ;;
		-w|--where)      need_arg "$@"; WHERE=$2; shift 2 ;;
		--sort)          need_arg "$@"; SORT=$2; shift 2 ;;
		--probe)         PROBE=true; shift ;;
		-q|--quiet)      QUIET=true; shift ;;
		-h|--help)       usage; exit 0 ;;
		-V|--version)    echo "$VERSION"; exit 0 ;;
		--)              shift; break ;;
		-*)              die "unknown option: $1 (see --help)" ;;
		*)
			if [ "$PROBE" = true ]; then
				PROBE_URIS="$PROBE_URIS$1
"
			else
				[ -z "$URI" ] || die "unexpected argument: $1 (see --help)"
				URI=$1
			fi
			shift ;;
	esac
done
[ $# -eq 0 ] || die "unexpected argument: $1 (see --help)"

if [ "$PROBE" = false ] && [ -z "$URI" ]; then
	usage >&2
	exit 1
fi
for u in $URI $PROBE_URIS; do
	case "$u" in
		content://*) ;;
		*) die "the URI should start with content:// (got: $u)" ;;
	esac
done

# ------------------------------------------------------------- find adb ---

find_adb() {
	local candidate
	if [ -n "${ADB:-}" ]; then
		[ -x "$ADB" ] || die "ADB is set to '$ADB' but it is not executable"
		echo "$ADB"
		return
	fi
	if command -v adb >/dev/null 2>&1; then
		command -v adb
		return
	fi
	for candidate in \
		"${ANDROID_HOME:-}/platform-tools/adb" \
		"${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
		"$HOME/Library/Android/sdk/platform-tools/adb" \
		"$HOME/Android/Sdk/platform-tools/adb" \
		"$HOME/android-sdk/platform-tools/adb"
	do
		if [ -x "$candidate" ]; then
			echo "$candidate"
			return
		fi
	done
	die "adb not found. Install Android platform-tools (macOS: brew install --cask android-platform-tools, Debian/Ubuntu: apt install adb) or set ADB=/path/to/adb"
}

ADB_BIN=$(find_adb)

# --------------------------------------------------------- check device ---

# Prints "<serial>\t<state>" for every device adb knows about.
list_devices() {
	"$ADB_BIN" devices 2>/dev/null | awk 'NR > 1 && NF >= 2 && $1 !~ /^\*/ { print $1 "\t" $2 }'
}

check_device() {
	local devices ready count state
	devices=$(list_devices)
	count=$(printf '%s' "$devices" | grep -c . || true)

	if [ "$count" -eq 0 ]; then
		die "no device found. Connect a device with USB debugging enabled (or start an emulator) and check 'adb devices'"
	fi

	if [ -z "$SERIAL" ]; then
		# Only devices in the "device" state can be queried; ignore the
		# offline and unauthorized ones when picking a default.
		ready=$(printf '%s\n' "$devices" | awk -F'\t' '$2 == "device" { print $1 }')
		case $(printf '%s' "$ready" | grep -c . || true) in
			0)
				if [ "$count" -eq 1 ]; then
					# let the state check below explain what is wrong with it
					SERIAL=$(printf '%s' "$devices" | cut -f1)
				else
					printf 'adb-export: no device is ready (offline devices need a reconnect, unauthorized ones need the USB debugging prompt accepted):\n' >&2
					printf '%s\n' "$devices" | sed 's/^/  /' >&2
					exit 1
				fi ;;
			1)
				SERIAL=$ready ;;
			*)
				printf 'adb-export: more than one device is ready, pick one with -s <serial>, e.g. -s %s:\n' "$(printf '%s\n' "$ready" | head -1)" >&2
				printf '%s\n' "$devices" | sed 's/^/  /' >&2
				exit 1 ;;
		esac
	fi

	state=$(printf '%s\n' "$devices" | awk -F'\t' -v s="$SERIAL" '$1 == s { print $2 }')
	case "$state" in
		device) ;;
		"")           die "device '$SERIAL' is not connected (check 'adb devices')" ;;
		unauthorized) die "device '$SERIAL' is unauthorized. Accept the USB debugging prompt on the device and try again" ;;
		offline)      die "device '$SERIAL' is offline. Reconnect it and try again" ;;
		*)            die "device '$SERIAL' is in state '$state' and cannot be queried" ;;
	esac
}

check_device

# ---------------------------------------------------------- build query ---

# Quote a string for the shell running on the device. adb joins its arguments
# with spaces and lets the remote shell parse them again, so anything with
# spaces or quotes (a where clause, a sort order) has to be quoted here.
shq() {
	local s=$1
	s=${s//\'/\'\\\'\'}
	printf "'%s'" "$s"
}

# Prints the 'content query' command line for a URI, with the query options.
query_cmd() {
	local cmd
	cmd="content query --uri $(shq "$1")"
	[ -z "$USER_ID" ]    || cmd="$cmd --user $(shq "$USER_ID")"
	[ -z "$PROJECTION" ] || cmd="$cmd --projection $(shq "$PROJECTION")"
	[ -z "$WHERE" ]      || cmd="$cmd --where $(shq "$WHERE")"
	[ -z "$SORT" ]       || cmd="$cmd --sort $(shq "$SORT")"
	printf '%s' "$cmd"
}

# ---------------------------------------------------------------- probe ---

# Content URIs that are known to answer on recent Android versions. Lines
# starting with '#' are section titles. Keep this list in sync with the README.
KNOWN_URIS=$(cat <<'EOF'
# Calendar
content://com.android.calendar/calendars
content://com.android.calendar/events
content://com.android.calendar/instances/when/0/9999999999999
content://com.android.calendar/attendees
content://com.android.calendar/reminders
content://com.android.calendar/calendar_alerts
content://com.android.calendar/extendedproperties
content://com.android.calendar/colors
content://com.android.calendar/event_entities
content://com.android.calendar/calendar_entities
content://com.android.calendar/syncstate
# Contacts
content://com.android.contacts/contacts
content://com.android.contacts/raw_contacts
content://com.android.contacts/raw_contact_entities
content://com.android.contacts/data
content://com.android.contacts/data/phones
content://com.android.contacts/data/emails
content://com.android.contacts/data/postals
content://com.android.contacts/data/callables
content://com.android.contacts/data/contactables
content://com.android.contacts/groups
content://com.android.contacts/directories
content://com.android.contacts/deleted_contacts
content://com.android.contacts/aggregation_exceptions
content://com.android.contacts/photo_dimensions
content://com.android.contacts/profile
content://com.android.contacts/settings
content://com.android.contacts/provider_status
content://com.android.contacts/syncstate
# Media
content://media/external/file
content://media/external/downloads
content://media/external/images/media
content://media/external/images/thumbnails
content://media/external/audio/media
content://media/external/audio/albums
content://media/external/audio/artists
content://media/external/audio/genres
content://media/external/audio/playlists
content://media/external/video/media
content://media/external/video/thumbnails
# Settings
content://settings/system
content://settings/secure
content://settings/global
# Telephony
content://sms
content://sms/inbox
content://sms/sent
content://sms/draft
content://mms
content://mms/part
content://mms-sms/conversations
content://mms-sms/canonical-addresses
content://call_log/calls
content://call_log_shadow/calls
content://com.android.blockednumber/blocked
content://com.android.voicemail/voicemail
content://com.android.voicemail/status
content://telephony/carriers
content://telephony/carriers/preferapn
content://icc/adn
content://cellbroadcasts
# Other
content://downloads/my_downloads
content://user_dictionary/words
EOF
)

# Runs one query on the device and prints a one word verdict, the row count
# (if any) and the error message (if any), tab separated.
probe_one() {
	local cmd out count first
	cmd=$(query_cmd "$1")
	# The row count is computed on the device so only two lines travel back.
	# The output goes through a temp file: the device shell has no built-in
	# printf and a big table does not fit in a command line.
	out=$("$ADB_BIN" -s "$SERIAL" shell "f=/data/local/tmp/adb-export-probe.\$\$; $cmd > \$f 2>&1; head -n 2 \$f; echo ROWCOUNT=\$(grep -c '^Row: ' \$f); rm -f \$f" 2>&1 </dev/null | tr -d '\r') || true
	count=$(printf '%s\n' "$out" | sed -n 's/^ROWCOUNT=//p' | tail -1)
	[ -n "$count" ] || count=$(printf '%s\n' "$out" | grep -c '^Row: ' || true)
	# Errors come as "Error while accessing provider:x" followed by the Java
	# exception; the exception line carries the useful message.
	first=$(printf '%s\n' "$out" | grep -m1 'Exception' | sed 's/^[A-Za-z0-9_.$]*Exception: *//' | cut -c1-90)

	if [ "$count" -gt 0 ]; then
		printf 'rows\t%s\t\n' "$count"
	elif printf '%s' "$out" | grep -q 'No result found'; then
		printf 'empty\t\t\n'
	elif printf '%s' "$out" | grep -q 'SecurityException'; then
		printf 'denied\t\t%s\n' "$first"
	elif printf '%s' "$out" | grep -q -E 'Could not find provider|Bad root path|Unknown URI|Unknown URL|Unsupported URI|not found'; then
		printf 'missing\t\t%s\n' "$first"
	else
		[ -n "$first" ] || first=$(printf '%s\n' "$out" | grep -v '^ROWCOUNT=' | head -1 | cut -c1-90)
		printf 'error\t\t%s\n' "$first"
	fi
}

probe() {
	local list line verdict count msg total=0
	local n_rows=0 n_empty=0 n_denied=0 n_missing=0 n_error=0

	if [ -n "$PROBE_URIS" ]; then
		list=$PROBE_URIS
	else
		list=$KNOWN_URIS
	fi
	total=$(printf '%s\n' "$list" | grep -c '^content://' || true)

	echo ""
	echo "Probing $total content URIs on $SERIAL"
	while IFS= read -r line; do
		case "$line" in
			"") continue ;;
			"#"*) echo ""; echo "${line#\# }"; continue ;;
		esac
		verdict=$(probe_one "$line")
		count=$(printf '%s' "$verdict" | cut -f2)
		msg=$(printf '%s' "$verdict" | cut -f3)
		verdict=$(printf '%s' "$verdict" | cut -f1)
		case "$verdict" in
			rows)    n_rows=$((n_rows + 1)) ;;
			empty)   n_empty=$((n_empty + 1)) ;;
			denied)  n_denied=$((n_denied + 1)) ;;
			missing) n_missing=$((n_missing + 1)) ;;
			*)       n_error=$((n_error + 1)) ;;
		esac
		printf '  %-8s %6s  %s' "$verdict" "$count" "$line"
		[ -z "$msg" ] || printf '  (%s)' "$msg"
		printf '\n'
	done <<EOF
$list
EOF
	echo ""
	echo "rows: $n_rows  empty: $n_empty  denied: $n_denied  missing: $n_missing  error: $n_error"
	echo ""
}

if [ "$PROBE" = true ]; then
	probe
	exit 0
fi

REMOTE_CMD=$(query_cmd "$URI")

# ------------------------------------------------------- output location ---

timestamp() { date +"%Y%m%d-%H%M%S"; }

# content://com.android.calendar/events -> com.android.calendar_events
uri_to_name() {
	printf '%s' "${1#content://}" | tr '/' '_' | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//'
}

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/adb-export.XXXXXX")
QUERY_PID=""
cleanup() {
	[ -z "$QUERY_PID" ] || kill "$QUERY_PID" 2>/dev/null || true
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

ERR_FILE="$TMP_DIR/stderr.txt"
META_FILE="$TMP_DIR/meta.txt"

if [ "$TO_STDOUT" = true ]; then
	EXPORT_DIR=""
	RAW_FILE="$TMP_DIR/raw_query.txt"
	CSV_FILE=""
else
	EXPORT_DIR="$OUT_DIR/$(uri_to_name "$URI")-$(timestamp)"
	mkdir -p "$EXPORT_DIR" || die "cannot create $EXPORT_DIR"
	RAW_FILE="$EXPORT_DIR/raw_query.txt"
	CSV_FILE="$EXPORT_DIR/data.csv"
fi

# ------------------------------------------------------------ run query ---

# Run a command in the background and show a spinner while it runs (only when
# stderr is a terminal). Returns the exit status of the command.
run_with_spinner() {
	local label=$1; shift
	local spin="|/-\\" i=0 rc=0

	"$@" &
	QUERY_PID=$!

	if [ "$QUIET" = false ] && [ -t 2 ]; then
		while kill -0 "$QUERY_PID" 2>/dev/null; do
			printf '\r - %s %s' "$label" "${spin:$((i % 4)):1}" >&2
			i=$((i + 1))
			sleep 0.1
		done
		printf '\r - %s   \n' "$label" >&2
	fi

	wait "$QUERY_PID" || rc=$?
	QUERY_PID=""
	return "$rc"
}

run_query() {
	"$ADB_BIN" -s "$SERIAL" shell "$REMOTE_CMD" > "$RAW_FILE" 2> "$ERR_FILE"
}

START_TIME=$(date +%s)
info ""
info "Exporting $URI from $SERIAL"

if ! run_with_spinner "Querying provider" run_query; then
	# Old adb versions cannot report the remote exit status, new ones do.
	# Either way the interesting part is the message.
	[ -s "$ERR_FILE" ] && cat "$ERR_FILE" >&2
	[ -s "$RAW_FILE" ] && cat "$RAW_FILE" >&2
	die "adb shell failed"
fi

# Some adb builds print the device stderr separately; keep it for diagnostics.
if [ -s "$ERR_FILE" ] && ! grep -q '^Row: ' "$RAW_FILE"; then
	cat "$ERR_FILE" >> "$RAW_FILE"
fi

# ---------------------------------------------------------- parse to CSV ---

# The output of 'content query' looks like (Content.java in AOSP):
#
#   Row: 0 _id=1, name=foo, value=bar
#   Row: 1 _id=2, name=NULL, value=BLOB
#
# Every row has the same columns in the same order. A value can contain
# commas, '=' signs and even newlines, so the line cannot simply be split on
# ", ". Instead:
#
#   1. Collect the "candidate" column names of every row: the token before
#      the first '=' and every ", token=" boundary. Column names never
#      contain spaces, so a token is anything without ',', '=' or a space.
#   2. A value that happens to contain ", word=" adds a bogus candidate, so
#      take the row with the fewest candidates and keep only the candidates
#      that occur in every row. That is the column list. (If every single
#      row has such a value the bogus column survives; pass --projection to
#      pin the columns in that case.)
#   3. Split each row again, this time looking only for the known ", column="
#      separators in order, and write the values as a CSV row.
#
# The raw file is read twice (steps 1-2, then 3) so only one row has to be
# kept in memory at a time.
AWK_PROGRAM=$(cat <<'EOF'
function flush_first_pass(   s, k, cnt) {
	if (rec == "") return
	s = rec
	sub(/^Row: [0-9]+ /, "", s)
	cnt = 0
	if (match(s, /^[^,= \n]+=/)) {
		k = substr(s, 1, RLENGTH - 1)
		cnt++
		if (seen_in[k] != nrows) { seen_in[k] = nrows; seen[k]++ }
		s = substr(s, RLENGTH + 1)
	}
	while (match(s, /, [^,= \n]+=/)) {
		k = substr(s, RSTART + 2, RLENGTH - 3)
		cnt++
		if (seen_in[k] != nrows) { seen_in[k] = nrows; seen[k]++ }
		s = substr(s, RSTART + RLENGTH)
	}
	if (best == 0 || cnt < best_count) { best = nrows; best_count = cnt; best_rec = rec }
	rec = ""
}

function pick_columns(   s, k) {
	s = best_rec
	sub(/^Row: [0-9]+ /, "", s)
	ncols = 0
	if (match(s, /^[^,= \n]+=/)) {
		k = substr(s, 1, RLENGTH - 1)
		if (seen[k] == nrows) col[++ncols] = k
		s = substr(s, RLENGTH + 1)
	}
	while (match(s, /, [^,= \n]+=/)) {
		k = substr(s, RSTART + 2, RLENGTH - 3)
		if (seen[k] == nrows) col[++ncols] = k
		s = substr(s, RSTART + RLENGTH)
	}
}

function csv_quote(v) {
	if (v ~ /[",\r\n]/) {
		gsub(/"/, "\"\"", v)
		return "\"" v "\""
	}
	return v
}

function flush_second_pass(   s, i, sep, pos, v, line) {
	if (rec == "") return
	s = rec
	sub(/^Row: [0-9]+ /, "", s)
	s = substr(s, length(col[1]) + 2)
	line = ""
	for (i = 1; i <= ncols; i++) {
		if (i < ncols) {
			sep = ", " col[i + 1] "="
			pos = index(s, sep)
			if (pos == 0) { v = s; s = "" }
			else { v = substr(s, 1, pos - 1); s = substr(s, pos + length(sep)) }
		} else {
			v = s
		}
		line = line (i > 1 ? "," : "") csv_quote(v)
	}
	print line
	rec = ""
}

# pass 1: count rows, find the column list
FNR == NR {
	sub(/\r$/, "")
	if ($0 ~ /^Row: [0-9]+ /) {
		flush_first_pass()
		nrows++
		rec = $0
	} else if (rec != "") {
		rec = rec "\n" $0
	} else {
		preamble = preamble $0 "\n"
	}
	next
}

# between the passes
FNR == 1 {
	flush_first_pass()
	if (nrows == 0) {
		if (preamble ~ /No result found/) {
			print "rows=0" > meta
			exit 0
		}
		printf "%s", preamble > "/dev/stderr"
		print "adb-export: the query returned no rows (see the message above)" > "/dev/stderr"
		exit 1
	}
	pick_columns()
	print "rows=" nrows > meta
	for (i = 1; i <= ncols; i++) print "col=" col[i] > meta
	for (i = 1; i <= ncols; i++) printf "%s%s", (i > 1 ? "," : ""), csv_quote(col[i])
	printf "\n"
	rec = ""
}

# pass 2: write the rows
{
	sub(/\r$/, "")
	if ($0 ~ /^Row: [0-9]+ /) {
		flush_second_pass()
		rec = $0
	} else if (rec != "") {
		rec = rec "\n" $0
	}
}

END {
	if (nrows > 0 && ncols > 0) flush_second_pass()
}
EOF
)

parse() {
	# LC_ALL=C makes awk work on bytes so UTF-8 passes through untouched.
	LC_ALL=C awk -v meta="$META_FILE" "$AWK_PROGRAM" "$RAW_FILE" "$RAW_FILE"
}

# An empty raw file means the first pass never ran; give awk one line so the
# "between the passes" block still executes.
if [ ! -s "$RAW_FILE" ]; then
	printf '\n' > "$RAW_FILE"
fi

if [ "$TO_STDOUT" = true ]; then
	parse
elif ! parse > "$CSV_FILE"; then
	rm -f "$CSV_FILE"
	info "The raw output was kept for debugging: $RAW_FILE"
	exit 1
fi

# -------------------------------------------------------------- summary ---

ROWS=$(sed -n 's/^rows=//p' "$META_FILE")
COLUMNS=$(sed -n 's/^col=//p' "$META_FILE" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
NUM_COLUMNS=$(grep -c '^col=' "$META_FILE" || true)
ELAPSED=$(( $(date +%s) - START_TIME ))

if [ "$ROWS" -eq 0 ]; then
	info " - The provider returned no rows"
	if [ "$TO_STDOUT" = false ]; then
		: > "$CSV_FILE"
	fi
else
	info " - Columns ($NUM_COLUMNS): $COLUMNS"
fi

info ""
info "Rows exported: $ROWS"
info "Elapsed:       ${ELAPSED}s"
if [ "$TO_STDOUT" = false ]; then
	info "Raw output:    $RAW_FILE"
	info "CSV:           $CSV_FILE"
fi
info ""
