#!/usr/bin/env bash

# steps:
# 1. query via adb and export the output to file
# 2. import the raw data
# 3. break to rows
# 4. write each transformed row to csv


# ============ GENERAL PARAMS =============
DEBUG=true
REPLACE_VALUE_COMMAS_TO=" "

EVENTS_URI="content://com.android.calendar/events"


# ========== CREATE WORKING DIR ===========
rawQueryFile="raw_query.txt"
> $rawQueryFile

outputFileName="result.csv"
> $outputFileName



# ============== FUNCTIONS ================

# find the first poistion of substring 
# params: 
#	- string we look in
#	- string we look for
# output:
#	- position of the first occurance
strindex() { 
	x="${1%%$2*}"
	[[ $x = $1 ]] && echo -1 || echo ${#x}
}

spinner() {
	echo $1
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
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

	# remove all "," and convert 
	row=$1
	# row=$(tr "," "$REPLACE_VALUE_COMMAS_TO" <<< "$1")

	for item in $row
	do
		# echo $item

		# skip the first two (they will be Row\n<number>)
		if [ $i -eq 0 -o $i -eq 1 ]; then
			if [ $i -eq 1 ]; then
				echo $item
			fi
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
		echo ${cols// /,} >> $outputFileName	
	fi
	
	# print values with comma separated
	vals=${values[*]}

	# print to file end escape new lines
	echo ${vals} | tr "\n\r" " " >> $outputFileName
	echo -n $'\n' >> $outputFileName

}

# containsElement () {
#   local e
#   for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
#   return 1
# }

# ========== RUN ADB CONENT CMD ===========

dbquery() {
	adb shell "
	content query --uri $EVENTS_URI
	" > $rawQueryFile
}

(dbquery) &
spinner "Querying DB"

# ============ EXPORT TO CSV ==============

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
    index=$(strindex "$line" "Row:")
    if [ $index -eq 0 ]; then
    	# this is a new row
    	let "count+=1"
    	rows[$count]=$(printf "%s" "$line")
    else 
    	# this is still the previous row
    	rows[$count]+=$(printf "%s" "$line")
    fi
done < "$rawQueryFile" 
# spinner "Reading rows"

for i in "${!rows[@]}"
do
	# for each row export to CSV
	toCsv "${rows[i]}" $(if [ $i -eq 0 ]; then echo "true"; else echo "false"; fi)
	
done 
# spinner "Writing to CSV"

# export results
echo "Result:"
echo $(printf "Num of rows: %d" "${#rows[@]}")


