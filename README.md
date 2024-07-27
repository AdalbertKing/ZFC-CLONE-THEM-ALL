# ZFS Snapshots and Synchronization Scripts

## Description

These scripts are designed to automate the process of creating, sending, and deleting ZFS snapshots. They support both local and remote operations and include features for compression and buffering.

### Authors

- Wojciech Król & ChatGPT-4o
- Email: lurk@lurk.com.pl
- Version: 1.1, 2024-07-27

## `snapsend02.sh`

### Description

`snapsend02.sh` is a script for creating and sending ZFS snapshots. It supports both local and remote destinations, with options for recursion, compression, and buffering.

### Usage

```bash
./snapsend.sh [options] <local_datasets> <remote>
Options

    -R: Enable recursive operation.
    <dataset_list>: Comma-separated list of datasets.
    <pattern>: Pattern to match snapshots for deletion.
    -y <years>: Specify the age in years.
    -m <months>: Specify the age in months.
    -w <weeks>: Specify the age in weeks.
    -d <days>: Specify the age in days.
    -h <hours>: Specify the age in hours.

Examples
Delete Hourly Snapshots Older Than 24 Hours
./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24
Delete Daily Snapshots Older Than 30 Days
./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30
Delete Weekly Snapshots Older Than 4 Weeks
./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4
Delete Monthly Snapshots Older Than 12 Months
./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12

cron.txt
Description

cron.txt provides example cron jobs for automating the execution of snapsend.sh and delsnaps.sh.
Content

MAILTO=""
SHELL=/bin/bash
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/root/skrypty:/root/scripts/zfs-snapshot-all

# Hourly snapshot
0 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
5 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:" 2>>/root/scripts/cron.log

# Daily snapshot
10 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
15 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:" 2>>/root/scripts/cron.log
16 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" "rpool/ROOT/pve-1" "192.168.28.8:hdd/kopie/pve1" 2>>/root/scripts/cron.log

# Weekly snapshot
20 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
25 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:" 2>>/root/scripts/cron.log

# Monthly snapshot
30 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
35 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:" 2>>/root/scripts/cron.log

# Delete old snapshots
40 * * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_hourly -h24 2>>/root/scripts/cron.log
46 0 * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_daily -d30 2>>/root/scripts/cron.log
48 0 * * 0 /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_weekly -w4 2>>/root/scripts/cron.log
50 0 1 * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_monthly -m12 2>>/root/scripts/cron.log
42 * * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks zincrsend_zincrsend -d31 2>>/root/scripts/cron.log





