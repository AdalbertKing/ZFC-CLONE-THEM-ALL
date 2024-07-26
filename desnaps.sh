#!/bin/bash

# Author: Wojciech KrĂłl & Chat-GPT 4
# Email: lurk@lurk.com.pl
# Ver: 1.0 from 2024-07-26

# Description:
# This script deletes ZFS snapshots based on a specified age threshold.

# Usage examples:
# 1. Delete snapshots older than 1 year and 6 months for datasets "tank/data1" and "tank/data2" recursively:
#    ./delsnaps.sh -R "tank/data1,tank/data2" "backup-" -y1 -m6 -d0 -h0
# 2. Delete snapshots older than 2 years without recursion for dataset "tank/data3":
#    ./delsnaps.sh "tank/data3" "snapshot-" -y2 -m0 -d0 -h0

# Options:
# -R                   : Recursively process child datasets.
# -y <years>           : Number of years.
# -m <months>          : Number of months.
# -w <weeks>           : Number of weeks.
# -d <days>            : Number of days.
# -h <hours>           : Number of hours.

# Function to display script usage
usage() {
    echo "Usage: $0 [-R] <comma-separated list of datasets> <pattern> -y<years> -m<months> -w<weeks> -d<days> -h<hours>"
    exit 1
}

# Function to parse time arguments
parse_time_arguments() {
    years=0
    months=0
    weeks=0
    days=0
    hours=0

    while getopts "y:m:w:d:h:" opt; do
        case ${opt} in
            y )
                years=$OPTARG
                ;;
            m )
                months=$OPTARG
                ;;
            w )
                weeks=$OPTARG
                ;;
            d )
                days=$OPTARG
                ;;
            h )
                hours=$OPTARG
                ;;
            \? )
                usage
                ;;
        esac
    done
}

# Function to calculate the threshold date
calculate_threshold_date() {
    echo $(date -d "-${years} years -${months} months -${weeks} weeks -${days} days -${hours} hours" +%s)
}

# Function to delete snapshots
delete_snapshots() {
    local ds="$1"
    local pat="$2"
    local th_date="$3"

    echo "Debug: Inside delete_snapshots function"
    echo "Debug: Dataset = $ds"
    echo "Debug: Pattern = $pat"

    snapshots=$(zfs list -H -o name -t snapshot -r "${ds}" | grep "${pat}")
    echo "Debug: Snapshots found: ${snapshots}"

    for snapshot in ${snapshots}; do
        creation_date=$(zfs get -H -o value creation "${snapshot}")
        creation_date_sec=$(date -d "${creation_date}" +%s)

        echo "Debug: Snapshot = $snapshot, creation_date = $creation_date, creation_date_sec = $creation_date_sec"

        if [ ${creation_date_sec} -lt ${th_date} ]; then
            echo "Deleting snapshot: ${snapshot}"
            zfs destroy -R "${snapshot}"
            if [ $? -ne 0 ]; then
                echo "Error deleting snapshot: ${snapshot}"
            fi
        else
            echo "Keeping snapshot: ${snapshot} (newer than threshold)"
        fi
    done
}

# Function to recursively process datasets
process_datasets_recursively() {
    local base_ds="$1"
    local pat="$2"
    local th_date="$3"

    delete_snapshots "${base_ds}" "${pat}" "${th_date}"

    child_datasets=$(zfs list -H -o name -t filesystem -r "${base_ds}" | grep -v "^${base_ds}$")
    for child in ${child_datasets}; do
        echo "Debug: Processing child dataset = $child"
        delete_snapshots "${child}" "${pat}" "${th_date}"
    done
}

# Main function to process datasets
process_datasets() {
    local recurse="$1"
    local datasets_list="$2"
    local pattern="$3"
    local threshold_date="$4"

    IFS=',' read -r -a datasets <<< "$datasets_list"

    for dataset in "${datasets[@]}"; do
        if [ "$recurse" = true ]; then
            process_datasets_recursively "${dataset}" "${pattern}" "${threshold_date}"
        else
            delete_snapshots "${dataset}" "${pattern}" "${threshold_date}"
        fi
    done
}

# Check number of arguments
if [ "$#" -lt 3 ]; then
    usage
fi

recurse=false

# Check if first argument is -R
if [ "$1" == "-R" ]; then
    recurse=true
    shift
fi

# Get arguments
datasets_list="$1"
shift
pattern="$1"
shift

# Parse time arguments
parse_time_arguments "$@"

# Calculate threshold date
threshold_date=$(calculate_threshold_date)
echo "Debug: threshold_date = $threshold_date ($(date -d "@$threshold_date"))"

# Process datasets
process_datasets "$recurse" "$datasets_list" "$pattern" "$threshold_date"
