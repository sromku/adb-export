# ADB-Export
Bash script that **exports** content provider's data to raw and CSV file format. It can be your own content provider or any other content provider that isn't blocked with permissions.

## Getting started

First, clone the repository using git:

``` bash
git clone https://github.com/snatik/adb-export/
```

or download the script manually using this command:

``` bash
curl "https://raw.githubusercontent.com/snatik/adb-export/master/adb-export.sh" -o adb-export.sh
```

Then give the execution permission to the script and run it:

``` bash
$ chmod +x adb-export.sh
$ ./adb-export.sh
```

## Usage

Enable `Developer options` on the device 

 * **-e [uri]**  - Set your provider URI and Export the data to CSV<br>

Example:
``` bash
./adb-export.sh -e content://com.your.app/images
```

Example:
``` bash
./adb-export.sh -e content://com.android.calendar/calendars
```

## Output
The exported data will be in a new created folders with timestamps in the same root folder this script is located. You will find two new created files:

 * `raw_query.txt` - this is what we exported from device
 * `data.csv` - this is what you need

## Permissions :unlock:

There is a list of some android content providers that don't block the adb query. My expectation was that it wouldn't be possible because of lack of provider permissions. Just to be on the safe side, I opened a security vulnarability issue to **[Security Google Team](http://www.google.co.il/about/appsecurity/)** and got few replies where the last one says that this is not a security hole.

Just an example:<br>

* This one won't work: `content://sms`<br>
The result will be: *requires android.permission.READ_SMS*

* This will work: `content://com.android.contacts/contacts`<br>
The result: CSV with all contacts<br>
Which, btw, should also check for permissions, but it **doesn't**. :open_mouth:

## Android content providers URIs :unlock:
If you discover some new that work, add them here

#### Calendar

 - content://com.android.calendar/calendars
 - content://com.android.calendar/events
 - content://com.android.calendar/attendees
 - content://com.android.calendar/reminders
 - content://com.android.calendar/extendedproperties

#### Contacts

 - content://com.android.contacts/contacts
 - content://com.android.contacts/directories
 - content://com.android.contacts/deleted_contacts
 - content://com.android.contacts/raw_contacts
 - content://com.android.contacts/data
 - content://com.android.contacts/data/phones
 - content://com.android.contacts/raw_contact_entities
 - content://com.android.contacts/status_updates
 - content://com.android.contacts/groups
 - content://com.android.contacts/aggregation_exceptions
 - content://com.android.contacts/photo_dimensions

#### Media

 - content://media/external/images/media
 - content://media/external/images/thumbnails
 - content://media/external/audio/media
 - content://media/external/audio/genres
 - content://media/external/audio/playlists
 - content://media/external/audio/artists
 - content://media/external/audio/albums
 - content://media/external/video/media
 - content://media/external/video/thumbnails

> the `external` in the uri, you can also change to `internal`

#### Settings

 - content://settings/system
 - content://settings/secure
 - content://settings/global
 - content://settings/bookmarks

#### Other

 - content://user_dictionary/words

## Tested Environments

* MacOSX
* Ubuntu 14.10 (Utopic). Run ```sudo apt-get install android-tools-adb``` first

If you have successfully tested this script on others systems or platforms please let me know or update this list.

## Important things to know

- Any commas in imported values are replaced to " " (space) char, since they don't play well in CSV format. You can configure it by changing `REPLACE_VALUE_COMMAS_TO` variable in the script.
- The table schema of the same android content provider on different devices can be different, thus the parsing steps try to understand what is the column and what is the value.
- This is the first version, and if you find bad parsing outputs, please open an issue.
- Use it only for good purposes!

## License
Apache License 2.0

See [LICENSE](./LICENSE.md) for details.

## Follow us

[![Twitter URL](https://img.shields.io/twitter/url/http/shields.io.svg?style=social)](https://twitter.com/intent/tweet?text=https://github.com/snatik/adb-export)
[![Twitter Follow](https://img.shields.io/twitter/follow/snatikteam.svg?style=social)](https://twitter.com/snatikteam)
