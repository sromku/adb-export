#!/usr/bin/env bash
# author: Roman Kushnarenko @sromku
# license: Apache License 2.0

uris=(
	"content://com.android.calendar/calendars"
	"content://com.android.calendar/events"
	)

description=(
	"Calendars table, which contains details of all calendars."
	"Events table, which contains details of all events."
	)


DEBUG=false
REPLACE_VALUE_COMMAS_TO=" "
SELECTED_URI=""

printOptions() {
options=""
option=1
for uri in ${uris[*]}
do
	options=$options$(printf "\n    %d      %s\n           %s" "$option" "$uri" "${description[option-1]}")$'\n'
	let "option+=1"
done

cat <<EOF

  Options:
$options
    -u     [uri] 
           Set any content provider uri. see example on github.   

  Examples:

  - Export content provider: content://com.android.calendar/events
    $ adb-export -o 2

  - Export any content provider like this: content://com.my.super.app/passwords
    $ adb-export -o -u content://com.my.super.app/passwords

EOF
}

wrongInput() {
cat <<EOF

  Wrong option selection. Check for available options: adb-export -o

EOF
}

# usage info
usage() {
cat <<EOF

  Usage: adb-export [options] [arg]

  Options:
	-o      List of content provider and exporting options 
	-h      This message

EOF
}

if [ $# -eq 0 ]; then
	usage;
	exit 1
fi

# options with 
if [ $# -eq 1 ]; then

	if [ $1 == '-o' ]; then
		printOptions;
  		exit 1
	fi

  	usage;
	exit 1
fi

# check one of standart options
if [ $# -eq 2 ]; then

	if [ $1 == '-o' ]; then

		if [ $2 -gt 0 -a $2 -le ${#uris[@]} ]; then
			# WE CAN START EXPORTING
			SELECTED_URI=${uris[$2-1]}
		else 
			wrongInput;
  			exit 1
		fi

	else 		
		printOptions;
		exit 1
	fi
	
fi

# check if custom one was selected
if [ $SELECTED_URI=="" ]; then
	if [ $# -eq 3 -a $1 == '-o' -a $2 == '-u' ]; then
		SELECTED_URI=$3
	else
		wrongInput;
	  	exit 1
	fi
fi

# create output file
timestamp() {
  date +"%H-%M-%S"
}

# steps:
# 1. query via adb and export the output to file
# 2. import the raw data & break to rows
# 3. write each transformed row to csv

# ============ GENERAL PARAMS =============

echo ""
echo "Exporting: $SELECTED_URI"

# ========== CREATE WORKING DIR ===========
DIR=$(pwd)$'/'${SELECTED_URI#'content://'}$'-'$(timestamp)
mkdir -p $DIR
RAW_QUERY_FILE=$DIR$'/'$'raw_query.txt'
OUTPUT_CSV=$DIR$'/'$'result.csv'

# ============== FUNCTIONS ================

# find the first poistion of substring 
# params: 
#	- string we look in
#	- string we look for
# return:
#	- position of the first occurance
strindex() { 
	x="${1%%$2*}"
	[[ $x = $1 ]] && echo -1 || echo ${#x}
}

# text with spin animation
spinner() {
	# echo $1
    local pid=$!
    local delay=0.05
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        toPrint=$(printf "[%c]  " "$spinstr")
        echo -ne " - $1: $toPrint \r"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    echo -ne " - $1: Done"
    echo ""
}

# convert android row to csv row
# params:
#	- android exported raw row
#	- boolean flag to tell if columns should be printed (in fact, this is valid for first row only)
toCsv() {

	# columns of row
	columns=()

	# values of row
	values=()

	# the key value
	keyValue=""

	# helper flag to aggregate items into keyvalue
	next=false

	# count number of fields
	i=0

	row=$1
	for item in $row
	do
		# skip the first two (they will be Row\n<number>)
		if [ $i -eq 0 -o $i -eq 1 ]; then
			let "i+=1"
			continue
		fi

		# if last char is "," then we have valid key=value
		keyValue=$(printf "%s" "${keyValue} ${item}")
		lastChar="${item: -1}"
		if [ $lastChar = "," ]; then
			keyValue=$(tr "," "$REPLACE_VALUE_COMMAS_TO" <<< "${keyValue%?}")
			keyValue+=","
			next=true 
		fi

		# if we have valid key value, then export to CSV
		if [ $next = true ]; then

			# fetch the column & value
			position=$(strindex "$keyValue" "=")
			# this is another assumtion, that column name can't be more than 30 lenght
			if [ $position -eq -1 -o $position -gt 30 ]; then
				# yes, it may happen and we will need to take this one and update the previous value
				lastPosition=${#values[@]}-1
				# add to previous one
				values[$lastPosition]=$(printf "%s" "${values[lastPosition]%?}${keyValue}")
				next=false
				keyValue=""
				continue
			else 
				let "i+=1"
			fi

			column=${keyValue:0:position}
			value=${keyValue:position+1}

			# -- DO IT ONLY FOR CSV --
			# except last char, replace all commas to make the CSV to be valid
			value="${value%?}"
			value=$(tr "," "$REPLACE_VALUE_COMMAS_TO" <<< "$value")
			value="${value},"
			# --^-----------------^--

			# aggregate columns and values
			columns+=($column)
			values+=($value)

			# go for next field
			next=false
			keyValue=""
		fi
		
	done

	# add last field 
	position=$(strindex "$keyValue" "=")
	column=${keyValue:0:position}
	value=${keyValue:(position+1)}
	columns+=($column)
	values+=($value)

	# check if we need to print columns
	if [ $2 == true ]; then

		# print columns with comma separated
		cols=${columns[*]}

		# print to file
		echo ${cols// /,} >> $OUTPUT_CSV
	fi
	
	# print values with comma separated
	vals=${values[*]}

	# print to file end escape new lines
	echo ${vals} | tr "\n\r" " " >> $OUTPUT_CSV
	echo -n $'\n' >> $OUTPUT_CSV

}

# give the percentage number
# params:
#	- part number
#	- total number
# return:
#	- the percentage
percent() {
	echo $(printf '%i %i' $1 $2 | awk '{ pc=100*$1/$2; i=int(pc); print (pc-i<0.5)?i:i+1 }')
}

# ========== RUN ADB CONENT CMD ===========

dbquery() {
	adb shell "
	content query --uri $SELECTED_URI
	" > $RAW_QUERY_FILE
}

# wait and show some spinner
(dbquery) &
spinner "Querying DB"

# ============ EXPORT TO CSV ==============

# prepare all rows in this array
declare -a rows

# number of lines

numOfLines=$(wc -l < "$RAW_QUERY_FILE")
readLines=0

# let's read line be line and build rows
count=-1
while read -r line
do
	# print
	let "readLines+=1"
	percentage=$(percent "$readLines" "$numOfLines")
	toPrint=$(printf " - Reading DB raw data: %d" "$percentage")
	echo -ne "$toPrint% \r"

	# it works as follow:
	# - we check if row starts with 'Row:', then we can assume that this is a new row (it's pretty NOT bad assumtion)
	# - the line that doesn't start with 'Row:' is something that contains fields and data whuch are belong to previous row
	# ref: https://android.googlesource.com/platform/frameworks/base/+/cd92588/cmds/content/src/com/android/commands/content/Content.java

	# the position of 'Row:' in the line
    index=$(strindex "$line" "Row:")
    if [ $index -eq 0 ]; then
    	# this is a new row
    	let "count+=1"
    	rows[$count]=$(printf "%s" "$line")
    else 
    	# this is still the previous row
    	rows[$count]+=$(printf "%s" "$line")
    fi

done < "$RAW_QUERY_FILE" 

# parse and write to csv
numOfRows=${#rows[@]}
readLines=0
echo ""
for i in "${!rows[@]}"
do

	# print
	let "readLines+=1"
	percentage=$(percent "$readLines" "$numOfRows")
	toPrint=$(printf " - Parsing and writing to CSV ($readLines/$numOfRows): %d" "$percentage")
	echo -ne "$toPrint% \r"

	# for each row export to CSV
	toCsv "${rows[i]}" $(if [ $i -eq 0 ]; then echo "true"; else echo "false"; fi)

done 
echo ""

# export results
echo "----------------------"
echo "Result:"
echo $(printf "Num of exported rows: %d" "$numOfRows")
echo ""

