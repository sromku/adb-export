#!/usr/bin/env bash

# start from 
#aa=(adb shell content query --uri content://com.android.calendar/events --where "dtstart > '1424131251000' and dtend < '1424217651000'" ))

#aa=(adb shell content query --uri content://com.android.calendar/events --where "allDay = 1 and dtstart > '1424044851000' and dtend < '1424304051000'" ))

# adb shell "
# content query --uri content://com.android.calendar/events
# " > res.txt

#echo `adb shell`
#echo `content query --uri content://com.android.calendar/events --where "dtstart > '1424131251000' and dtend < '1424217651000'"`

DEBUG=true
outputFileName="result.csv"

# clean the file
> $outputFileName

strindex() { 
  x="${1%%$2*}"
  [[ $x = $1 ]] && echo -1 || echo ${#x}
}

# function to convert android row to csv row
# row example:
#	Row: 0 sync_data10=NULL, cal_sync6=NULL, rrule=NULL, sync_data6=NULL, cal_sync8=1423664730492, eventTimezone=Asia/Jerusalem, _sync_id=pcr4ma0g31n6m0e76c6cno4i10_20150217T080000Z, hasAttendeeData=1, customAppPackage=NULL, originalInstanceTime=1424160000000, sync_data2=NULL, allowedReminders=0,1,2, calendar_timezone=Asia/Jerusalem, uid2445=NULL, dirty=0, originalAllDay=0, cal_sync10=NULL, calendar_color=-6306073, exrule=NULL, cal_sync3=NULL, lastDate=1424161800000, canOrganizerRespond=1, guestsCanSeeGuests=1, rdate=NULL, account_type=com.google, eventEndTimezone=NULL, selfAttendeeStatus=0, cal_sync2=NULL, mutators=NULL, exdate=NULL, hasExtendedProperties=0, calendar_color_index=15, organizer=nir@everything.me, eventColor_index=NULL, sync_data9=0, cal_sync5=0, eventColor=NULL, cal_sync4=1, availability=0, ownerAccount=nir@everything.me, dtstart=1424160000000, lastSynced=0, duration=NULL, accessLevel=0, maxReminders=5, displayColor=-6306073, allDay=0, dtend=1424161800000, eventStatus=1, sync_data3=NULL, sync_data4="2835027570380000", original_id=NULL, _id=1215, guestsCanModify=0, calendar_access_level=100, customAppUri=NULL, calendar_displayName=nir@everything.me, sync_data5=2014-12-02T09:49:45.000Z, guestsCanInviteOthers=1, sync_data8=NULL, cal_sync9=NULL, original_sync_id=pcr4ma0g31n6m0e76c6cno4i10, cal_sync1=nir@everything.me, cal_sync7=NULL, canModifyTimeZone=1, visible=1, allowedAttendeeTypes=0,1,2, sync_data1=pcr4ma0g31n6m0e76c6cno4i10@google.com, allowedAvailability=0,1, description=, title=, calendar_id=11, sync_data7=NULL, deleted=0, eventLocation=, account_name=roman@everything.me, hasAlarm=0, isOrganizer=1
toCsv() {
	# $1 - the row (string)
	# $2 - print columns (boolean)

	columns=()
	values=()

	showColumns=$2
	i=0

	# the key value
	keyValue=""
	next=false

	for item in $1
	do
		# skip the first two (they will be Row\n<number>)
		if [ $i -eq 0 -o $i -eq 1 ]; then
			let "i+=1"
			continue
		fi

		# if [ $2 = true ]; then 
		# 	echo $item
		# fi

		next=false

		# last char
		concat="${keyValue}${item}"
		# concat=$(printf "%s %s" "$keyValue $item")
		keyValue=$(printf "%s" "$concat")
		#$(printf "%s %s" "$keyValue" "$item")
		# if [ $2 = true ]; then 
		# 	echo $keyValue
		# fi
		lastChar="${item: -1}"
		if [ $lastChar = "," ]; then
			let "i+=1"
			next=true 
		fi

		if [ $next = true ]; then
			# if [ $2 = true ]; then 
			# 	echo $keyValue
			# 	echo "---"
			# fi

			position=$(strindex "$keyValue" "=")
			column=${keyValue:0:position}
			value=${keyValue:position+1}

			# DO IT ONLY FOR CSV
			# except last char and replace all commas in value to space
			value="${value%?}"
			value=$(tr ',' ' ' <<< "$value")
			value="${value},"

			columns+=($column)
			values+=($value)

			next=false
			keyValue=""
		fi
		
	done

	# add last one
	position=$(strindex "$keyValue" "=")
	column=${keyValue:0:position}
	value=${keyValue:(position+1)}
	columns+=($column)
	values+=($value)
	let "i+=1"

	# check if we need to print columns
	if [ $2 == true ]; then

		# print columns with comma separated
		cols=${columns[*]}

		# print to file
		echo ${cols// /,} >> $outputFileName	
	fi
	
	# print values with comma separated
	vals=${values[*]}

	# print to file end escape new lines
	echo ${vals} | tr "\n\r" " " >> $outputFileName
	echo -n $'\n' >> $outputFileName

}

# some dificulties:
# - it could be new lines in the middle and '+=' doesn't work with just $line. we should use printf string format
# - we can't match by '=' or by ',' since these chars could be part of the field value itself
# - i don't want to match with predefined field names, but keep it dynamic
# - new lines in values

file="raw_query.txt"
seperator="Row:"

# prepare all rows in this array
declare -a rows

# rows counter
count=-1

# let's read line be line and build rows
while read -r line
do
	# it works as follow:
	# - we check if row starts with 'Row:', then we can assume that this is a new row (not pretty bad assumtion after many tests)
	# - the line that doesn't start with 'Row:' is something that contains fields and data whuch are belong to previous row

	# the position of 'Row:' in the line
    index=$(strindex "$line" "$seperator")
    if [ $index -eq 0 ]; then
    	# this is a new row
    	let "count+=1"
    	rows[$count]=$(printf "%s" "$line")
    else 
    	# this is still the previous row
    	rows[$count]+=$(printf "%s" "$line")
    fi
done < "$file"

# print all rows
if [ $DEBUG = true ]; then
	for i in "${!rows[@]}"
	do
		echo ${rows[i]}
	done
	echo "===================="
fi

# time to fetch all playing field names :)
# the way to do it:
# - we take first row
# - iterate over items and check if item ends with ','
for i in "${!rows[@]}"
do
	toCsv "${rows[i]}" $(if [ $i -eq 0 ]; then echo "true"; else echo "false"; fi)
done

# declare -a columns
# firstRow=${rows[5]}
# for item in $firstRow; do
# 	echo $item
# done 

# export results
echo "Result:"
echo $(printf "Num of rows: %d" "${#rows[@]}")


