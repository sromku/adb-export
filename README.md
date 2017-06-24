# adb-export
Bash script that **exports** content provider's data to raw and CSV format. It can be your own content provider or any other content provider that isn't blocked with permissions.

## Getting started

First, clone the repository using git (recommended):

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

 * **[content://com.android.calendar/calendars](http://developer.android.com/reference/android/provider/CalendarContract.Calendars.html)**
 * **[content://com.android.calendar/events](http://developer.android.com/reference/android/provider/CalendarContract.Events.html)**
 * **[content://com.android.calendar/attendees](http://developer.android.com/reference/android/provider/CalendarContract.Attendees.html)**
 * **[content://com.android.calendar/reminders](http://developer.android.com/reference/android/provider/CalendarContract.Reminders.html)**
 * **[content://com.android.calendar/extendedproperties](http://developer.android.com/reference/android/provider/CalendarContract.ExtendedProperties.html)**

#### Contacts

 * **[content://com.android.contacts/contacts](http://developer.android.com/reference/android/provider/CalendarContract.Calendars.html)**
 * **[content://com.android.contacts/directories](http://developer.android.com/reference/android/provider/ContactsContract.Directory.html)**
 * content://com.android.contacts/deleted_contacts
 * **[content://com.android.contacts/raw_contacts](http://developer.android.com/reference/android/provider/ContactsContract.RawContacts.html)**
 * **[content://com.android.contacts/data](http://developer.android.com/reference/android/provider/ContactsContract.Data.html)**
 * **[content://com.android.contacts/raw_contact_entities](http://developer.android.com/reference/android/provider/ContactsContract.RawContactsEntity.html)**
 * content://com.android.contacts/status_updates
 * **[content://com.android.contacts/groups](http://developer.android.com/reference/android/provider/ContactsContract.Groups.html)**
 * **[content://com.android.contacts/aggregation_exceptions](http://developer.android.com/reference/android/provider/ContactsContract.AggregationExceptions.html)**
 * content://com.android.contacts/photo_dimensions

#### Media

 * **[content://media/external/images/media](http://developer.android.com/reference/android/provider/MediaStore.Images.Media.html)**
 * **[content://media/external/images/thumbnails](http://developer.android.com/reference/android/provider/MediaStore.Images.Thumbnails.html)**
 * **[content://media/external/audio/media](http://developer.android.com/reference/android/provider/MediaStore.Audio.Media.html)**
 * **[content://media/external/audio/genres](http://developer.android.com/reference/android/provider/MediaStore.Audio.Genres.html)**
 * **[content://media/external/audio/playlists](http://developer.android.com/reference/android/provider/MediaStore.Audio.Playlists.html)**
 * **[content://media/external/audio/artists](http://developer.android.com/reference/android/provider/MediaStore.Audio.Artists.html)**
 * **[content://media/external/audio/albums](http://developer.android.com/reference/android/provider/MediaStore.Audio.Albums.html)**
 * **[content://media/external/video/media](http://developer.android.com/reference/android/provider/MediaStore.Video.Media.html)**
 * **[content://media/external/video/thumbnails](http://developer.android.com/reference/android/provider/MediaStore.Video.Thumbnails.html)**

> the `external` in the uri, you can also change to `internal`

#### Settings

 * **[content://settings/system](http://developer.android.com/reference/android/provider/Settings.System.html)**
 * **[content://settings/secure](http://developer.android.com/reference/android/provider/Settings.Secure.html)**
 * **[content://settings/global](http://developer.android.com/reference/android/provider/Settings.Global.html)**
 * content://settings/bookmarks

#### Other

 * **[content://user_dictionary/words](http://developer.android.com/reference/android/provider/UserDictionary.Words.html)**

## Tested Environments (meanwhile)

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
