# adb-export

Bash script that **exports** the rows of an Android content provider to CSV over `adb`. It works with your own app's content provider or with any system provider that the `adb shell` user is allowed to read.

```
$ ./adb-export.sh content://settings/global

Exporting content://settings/global from emulator-5554
 - Columns (4): _id, name, value, is_preserved_in_restore

Rows exported: 189
Elapsed:       2s
Raw output:    ./exports/settings_global-20260907-221655/raw_query.txt
CSV:           ./exports/settings_global-20260907-221655/data.csv
```

## Requirements

* `adb` from the Android platform-tools. It is found on `PATH` or in the usual SDK locations (`$ANDROID_HOME`, `~/Library/Android/sdk`, `~/Android/Sdk`). You can also point to it with `ADB=/path/to/adb`.
  * macOS: `brew install --cask android-platform-tools`
  * Debian/Ubuntu: `sudo apt install adb`
* `bash` 3.2 or newer and `awk` (any flavour: BSD awk, gawk, mawk, busybox).
* A device or emulator with **USB debugging** enabled (`Settings > Developer options`).

## Getting started

Clone the repository:

```bash
git clone https://github.com/sromku/adb-export.git
```

or download the script directly:

```bash
curl -O https://raw.githubusercontent.com/sromku/adb-export/master/adb-export.sh
chmod +x adb-export.sh
```

Then run it with the URI of the content provider you want to export:

```bash
./adb-export.sh content://com.android.calendar/events
```

## Usage

```
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
```

Examples:

```bash
# export a provider to ./exports/<provider>-<timestamp>/data.csv
./adb-export.sh content://com.android.contacts/contacts

# pick a device when several are connected
./adb-export.sh -s emulator-5554 content://settings/secure

# only some columns, filtered and sorted (the provider has to support it)
./adb-export.sh content://settings/secure -p name:value --sort "name ASC"
./adb-export.sh content://settings/global -w "name='adb_wifi_enabled'"

# see which of the well known providers answer on this device
./adb-export.sh --probe
./adb-export.sh --probe content://com.your.app/items content://com.your.app/tags

# pipe the CSV somewhere else
./adb-export.sh -c content://media/external/images/media > images.csv
./adb-export.sh -c -q content://settings/system | column -s, -t
```

## Choosing a device

When one device is ready the script uses it. Offline and unauthorized devices are ignored, so a phone next to a couple of dead emulators still works without options. When several devices are ready you have to pick one:

```
$ ./adb-export.sh --probe
adb-export: more than one device is ready, pick one with -s <serial>, e.g. -s 57221FDCH009VC:
  57221FDCH009VC	device
  emulator-5554	device
$ ./adb-export.sh --probe -s emulator-5554
```

Setting `ANDROID_SERIAL` in your shell has the same effect as `-s` and saves repeating it.

## Output

By default every export creates a folder `exports/<provider>-<timestamp>/` in the current directory with two files:

* `raw_query.txt` - the untouched output of `adb shell content query`, useful when something looks off.
* `data.csv` - the parsed data, one header line followed by one line per row.

The CSV follows RFC 4180: values containing commas, quotes or newlines are quoted, and quotes inside a value are doubled. Nothing is altered otherwise. `NULL` and `BLOB` appear literally because that is how the device prints null values and binary columns.

## How the parsing works

`content query` prints one line per row, in the form `Row: 0 col1=value, col2=value, ...`. Values can themselves contain commas, `=` signs and newlines, so the line cannot simply be split on `, `. The script instead collects the candidate column names of every row (the tokens right before a `=` at each `, ` boundary), takes the row with the fewest candidates and keeps only the names that occur in every row. Those are the columns. Each row is then split again using only the known `, column=` separators, in order.

This handles the usual troublemakers (`value=a, b, c`, `value=x=y`, multi-line text, prose like `Hi, dear friend=of mine`). It can still be fooled when *every* row contains a value with the pattern `, word=` where `word` looks like a column name. If that happens, pass `--projection` with the real column names.

## Permissions

The query runs as the `shell` user on the device, which holds a fixed set of permissions (contacts, calendar, media, settings, call log, SMS and more). Providers that need a permission the shell user does not have answer with a `SecurityException`; the script prints the message and exits with status 1.

Years ago this was reported to the Google security team, who confirmed that the shell user being able to read these providers is intended behaviour.

## Content provider URIs that are known to work

All of these answer on an Android 16 emulator and on a Pixel running Android 17 (the full list was probed on both: no denials, nothing missing). Run `./adb-export.sh --probe` to check them against your own device: it prints, for every URI, whether it returned rows, was empty, was denied or does not exist. The probe writes each result to a temporary file under `/data/local/tmp` on the device and removes it again. Add the ones you discover.

```
$ ./adb-export.sh --probe

Probing 62 content URIs on emulator-5554

Calendar
  empty            content://com.android.calendar/calendars
  ...
Settings
  rows         38  content://settings/system
  rows        147  content://settings/secure
  rows        189  content://settings/global
  ...

rows: 13  empty: 49  denied: 0  missing: 0  error: 0
```

Unknown or blocked URIs are reported too, with the reason:

```
$ ./adb-export.sh --probe content://settings/bookmarks content://telephony/siminfo

Probing 2 content URIs on emulator-5554
  missing          content://settings/bookmarks  (Bad root path: bookmarks)
  denied           content://telephony/siminfo  (Access SIMINFO table from not phone/system UID)

rows: 0  empty: 0  denied: 1  missing: 1  error: 0
```

#### Calendar

- content://com.android.calendar/calendars
- content://com.android.calendar/events
- content://com.android.calendar/instances/when/`<start_ms>`/`<end_ms>` (recurring events expanded)
- content://com.android.calendar/attendees
- content://com.android.calendar/reminders
- content://com.android.calendar/calendar_alerts
- content://com.android.calendar/extendedproperties
- content://com.android.calendar/colors
- content://com.android.calendar/event_entities
- content://com.android.calendar/calendar_entities
- content://com.android.calendar/syncstate

#### Contacts

- content://com.android.contacts/contacts
- content://com.android.contacts/raw_contacts
- content://com.android.contacts/raw_contact_entities
- content://com.android.contacts/data
- content://com.android.contacts/data/phones
- content://com.android.contacts/data/emails
- content://com.android.contacts/data/postals
- content://com.android.contacts/data/callables
- content://com.android.contacts/data/contactables
- content://com.android.contacts/groups
- content://com.android.contacts/directories
- content://com.android.contacts/deleted_contacts
- content://com.android.contacts/aggregation_exceptions
- content://com.android.contacts/photo_dimensions
- content://com.android.contacts/profile (the "Me" contact)
- content://com.android.contacts/settings
- content://com.android.contacts/provider_status
- content://com.android.contacts/syncstate

#### Media

- content://media/external/file (every file the media store knows about)
- content://media/external/downloads
- content://media/external/images/media
- content://media/external/images/thumbnails
- content://media/external/audio/media
- content://media/external/audio/albums
- content://media/external/audio/artists
- content://media/external/audio/genres
- content://media/external/audio/playlists
- content://media/external/video/media
- content://media/external/video/thumbnails

> `external` can be replaced with `internal`, or with a volume name such as `external_primary`. The thumbnails, genres and playlists tables are deprecated since Android 10 and are usually empty.

#### Settings

- content://settings/system
- content://settings/secure
- content://settings/global
- content://settings/global/`<name>` (and the same for system and secure) returns a single setting

#### Telephony

- content://sms, content://sms/inbox, content://sms/sent, content://sms/draft
- content://mms, content://mms/part
- content://mms-sms/conversations
- content://mms-sms/canonical-addresses
- content://call_log/calls
- content://call_log_shadow/calls
- content://com.android.blockednumber/blocked
- content://com.android.voicemail/voicemail
- content://com.android.voicemail/status
- content://telephony/carriers, content://telephony/carriers/preferapn
- content://icc/adn (SIM phonebook)
- content://com.android.simphonebook/subid/`<subscription id>`/adn (Android 12 and later, needs an active SIM)
- content://cellbroadcasts

#### Other

- content://downloads/my_downloads
- content://user_dictionary/words

#### Gone or blocked

- `content://settings/bookmarks` and `content://browser/bookmarks` no longer exist: the AOSP browser was removed in Android 6 and Chrome does not expose its bookmarks.
- `content://com.android.contacts/contacts/frequent` and `strequent` answer but have been empty since Android 10.
- `content://telephony/siminfo`, `content://downloads/all_downloads` and the providers of Google apps (Clock, Keep, Messages, Dialer, Calendar tasks) refuse the shell user with a `SecurityException` or "No external queries".

## Tested environments

* macOS 26 with the stock bash 3.2 and BSD awk
* Ubuntu 24.04 (mawk and gawk) and Alpine 3.20 (busybox awk)
* Android 16 emulator and a Pixel running Android 17, with platform-tools 36. The complete `--probe` list answers on both.

## Development

The test suite replaces `adb` with a small fake and checks the parser, the option handling and the device checks:

```bash
./test/run.sh
```

## License

Apache License 2.0, see [LICENSE](./LICENSE).
