# adb-export
Bash script that exports Android content provider's data to CSV. And there is a lot of them and no android permissions are needed (and this is the funny part). Just take your device, connect to the comp and start exporting the data.

## Getting started

First, clone the repository using git (recommended):

``` bash
git clone https://github.com/sromku/adb-export/
```

or download the script manually using this command:

``` bash
curl "https://raw.githubusercontent.com/sromku/adb-export/master/adb-export.sh" -o adb-export.sh
```

Then give the execution permission to the script and run it:

``` bash
$ chmod +x adb-export.sh
$ ./adb-export.sh
```

## Usage

 * **-e [uri]**  - Export any content provider uri to CSV
Example:
``` bash
./adb-export.sh -e content://com.android.calendar/calendars
```

## Output
The exported data will be in a new created folders with timestamps where this script is located. You will find two new created files:

 * `raw_query.txt` - this is what we exported from device
 * `data.csv` - this is what you need

## Tested Environments (meanwhile)

* MacOSX

If you have successfully tested this script on others systems or platforms please let me know or update this list.

## Important things to know

- Any commas in imported values are replaced to " " (space) char, since they don't play well in CSV format. You can configure it by changing `REPLACE_VALUE_COMMAS_TO` variable in the script

