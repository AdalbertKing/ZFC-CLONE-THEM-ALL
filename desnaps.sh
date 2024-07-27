#!/bin/bash

# Author: Wojciech Król & ChatGPT-4o
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

# Delete Hourly Snapshots Older Than 24 Hours:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24

# Delete Daily Snapshots Older Than 30 Days:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30

# Delete Weekly Snapshots Older Than 4 Weeks:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4

# Delete Monthly Snapshots Older Than 12 Months:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12

# Sprawdzenie liczby argumentów
if [ "$#" -lt 3 ]; then
    usage
fi

recurse=false

# Sprawdzenie, czy pierwszy argument to -R
if [ "$1" == "-R" ]; then
    recurse=true
    shift
fi

# Pobranie argumentów
datasets_list="$1"
shift
pattern="$1"
shift

# Funkcja do wyświetlania użycia skryptu
usage() {
    echo "Użycie: $0 [-R] <lista datasetów oddzielonych przecinkami> <maska> -y<years> -m<months> -w<weeks> -d<days> -h<hours>"
    exit 1
}

# Funkcja do parsowania argumentów czasu
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

# Funkcja do obliczenia daty granicznej
calculate_threshold_date() {
    echo $(date -d "-${years} years -${months} months -${weeks} weeks -${days} days -${hours} hours" +%s)
}

# Funkcja do usuwania migawek
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
            echo "Usuwanie migawki: ${snapshot}"
            zfs destroy -R "${snapshot}"
            if [ $? -ne 0 ]; then
                echo "Błąd podczas usuwania migawki: ${snapshot}"
            fi
        else
            echo "Zachowanie migawki: ${snapshot} (nowsza niż threshold)"
        fi
    done
}

# Funkcja do przetwarzania datasetów rekurencyjnie
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

# Funkcja główna do przetwarzania datasetów
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

# Parsowanie argumentów czasu
parse_time_arguments "$@"

# Obliczenie daty granicznej
threshold_date=$(calculate_threshold_date)
echo "Debug: threshold_date = $threshold_date ($(date -d "@$threshold_date"))"

# Przetwarzanie datasetów
process_datasets "$recurse" "$datasets_list" "$pattern" "$threshold_date"
