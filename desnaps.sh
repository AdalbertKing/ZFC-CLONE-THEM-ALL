#!/bin/bash

# Author: Wojciech Król & ChatGPT-4
# Email: lurk@lurk.com.pl
# Version: 1.1, 2024-07-27

# Description:
# This script automates the process of deleting old ZFS snapshots based on specified age criteria.
# It supports recursive operations for specified datasets.

# Usage:
# ./delsnaps.sh [-R] <dataset_list> <pattern> -y<years> -m<months> -w<weeks> -d<days> -h<hours>

# Options:
# -R                         Enable recursive operation.
# <dataset_list>             Comma-separated list of datasets.
# <pattern>                  Pattern to match snapshots for deletion.
# -y <years>                 Specify the age in years.
# -m <months>                Specify the age in months.
# -w <weeks>                 Specify the age in weeks.
# -d <days>                  Specify the age in days.
# -h <hours>                 Specify the age in hours.

# Examples:
# 1. Delete Hourly Snapshots Older Than 24 Hours:
#    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24
# 2. Delete Daily Snapshots Older Than 30 Days:
#    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30
# 3. Delete Weekly Snapshots Older Than 4 Weeks:
#    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4
# 4. Delete Monthly Snapshots Older Than 12 Months:
#    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12

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

    # Parse the time-related options
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

    # Get the list of snapshots matching the pattern
    snapshots=$(zfs list -H -o name -t snapshot -r "${ds}" | grep "${pat}")
    echo "Debug: Snapshots found: ${snapshots}"

    for snapshot in ${snapshots}; do
        # Get the creation date of the snapshot
        creation_date=$(zfs get -H -o value creation "${snapshot}")
        creation_date_sec=$(date -d "${creation_date}" +%s)

        echo "Debug: Snapshot = $snapshot, creation_date = $creation_date, creation_date_sec = $creation_date_sec"

        # Check if the snapshot is older than the threshold date
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

    # Delete snapshots in the base dataset
    delete_snapshots "${base_ds}" "${pat}" "${th_date}"

    # Get the list of child datasets
    child_datasets=$(zfs list -H -o name -t filesystem -r "${base_ds}" | grep -v "^${base_ds}$")
    for child in ${child_datasets}; do
        echo "Debug: Processing child dataset = $child"
        # Delete snapshots in the child datasets
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
            # Process datasets recursively
            process_datasets_recursively "${dataset}" "${pattern}" "${threshold_date}"
        else
            # Process datasets non-recursively
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
