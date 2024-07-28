README.md
Snapsend.sh
Author: Wojciech Król & ChatGPT-4o
Version: 1.65, 2024-07-28
Overview

snapsend.sh is a robust script designed for ZFS snapshot management, supporting various configurations for local and remote operations, including compression, buffering, and forceful full send in case of incremental send failure.
Modes of Operation

The script supports three distinct modes of operation:

    Local Mode: Transfers snapshots within the same server.
    Remote Backup Mode: Transfers snapshots to a remote backup server.
    Remote Synchronization Mode: Keeps datasets synchronized between local and remote servers.

Script Options

    -m: Custom snapshot prefix.
    -u: Custom SSH user.
    -k: SSH password.
    -p: SSH port (default: 22).
    -R: Recursion for datasets.
    -b: Use mbuffer for buffering.
    -z: Use gzip for compression.
    -f: Force full send if incremental fails.
    -F: Force full send immediately.
    -v: Verbose level (1: minimal, 2: normal, 3: debug).
    usage:
    ./snapsend.sh [-m snapshot_prefix] [-u remote_user] [-k password] [-p remote_port] [-R] [-b] [-z] [-f] [-F] [-v verbose_level] local_datasets remote

    Examples:
Local Mode
./snapsend.sh -m "automated_hourly_" -R -F "hdd/test/hv1" "hdd/kopie"
This command creates and sends snapshots of hdd/test/hv1 to hdd/kopie with recursion and forceful full send.

This command creates and sends snapshots of hdd/test/hv1 to the remote server 192.168.28.8 under /backups using SSH with the specified user and password.

Remote Synchronization Mode
./snapsend.sh -m "automated_hourly_" -R -F -u "root" -k "password" "rpool/data/vm-100-disk-0" "192.168.28.8:/backups"

This command keeps the dataset rpool/data/vm-100-disk-0 synchronized between the local server and the remote server at 192.168.28.8:/backups.
Warnings and Considerations
Using -f and -F

Using -f (force incremental) in combination with -R (recursive) can lead to a full send for all child datasets if an issue occurs with one of them. This can result in long transfer times and high network usage. Use with caution.
Scenario:
Imagine a Proxmox server with multiple large virtual machines. If an admin accidentally deletes the last snapshot for rpool/data/vm-100-disk-0, the target server will have one redundant snapshot. This will prevent an incremental ZFS send. Using the script with ./snapsend.sh -m "automated_hourly_" -R -f "rpool/data/vm-disks" "192.168.28.8:hdd/kopie" will trigger a full ZFS send for all VMs from source to target, after performing zfs destroy hdd/kopie/rpool/data/vm-disks. This can lead to hours of network load and halt the transfer of other snapshots.
# delsnaps.sh

## Author
Wojciech Król & ChatGPT-4

## Email
lurk@lurk.com.pl

## Version
1.1 from 2024-07-27

## Description
This script automates the process of deleting old ZFS snapshots based on specified age criteria. It supports recursive operations for specified datasets.

## Usage
/delsnaps.sh [-R] <comma-separated list of datasets> <pattern> -y<years> -m<months> -w<weeks> -d<days> -h<hours>

### Options
- `-R`                         : Recursively process child datasets.
- `<comma-separated list of datasets>` : List of datasets to process, separated by commas.
- `<pattern>`                  : Pattern to match snapshots for deletion.
- `-y <years>`                 : Specify the age in years.
- `-m <months>`                : Specify the age in months.
- `-w <weeks>`                 : Specify the age in weeks.
- `-d <days>`                  : Specify the age in days.
- `-h <hours>`                 : Specify the age in hours.

## Examples

1. **Delete Hourly Snapshots Older Than 24 Hours:**
    ```bash
    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24
    ```
    This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_hourly` that are older than 24 hours.

2. **Delete Daily Snapshots Older Than 30 Days:**
    ```bash
    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30
    ```
    This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_daily` that are older than 30 days.

3. **Delete Weekly Snapshots Older Than 4 Weeks:**
    ```bash
    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4
    ```
    This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_weekly` that are older than 4 weeks.

4. **Delete Monthly Snapshots Older Than 12 Months:**
    ```bash
    ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12
    ```
    This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_monthly` that are older than 12 months.

## Script

```bash
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

# Delete Hourly Snapshots Older Than 24 Hours:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24

# Delete Daily Snapshots Older Than 30 Days:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30

# Delete Weekly Snapshots Older Than 4 Weeks:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4

# Delete Monthly Snapshots Older Than 12 Months:
# ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12

# Check number of arguments

License

This project is licensed under the MIT License - see the LICENSE file for details.






Contact

For any further questions or issues, please contact the author at lurk@lurk.com.pl.



