<<<<<<< HEAD
# ZFS Snapshots and Synchronization Scripts
=======

### Plik `README.md` (angielski)

```markdown
# ZFS-snaps-remote-clone-synchro-and-delete
>>>>>>> f7245a0d3d9311ebac2c4ce80fbfff7cba3132ab

## Description

These scripts are designed to automate the process of creating, sending, and deleting ZFS snapshots. They support both local and remote operations and include features for compression and buffering.

### Authors

- Wojciech Król & ChatGPT-4o
- Email: lurk@lurk.com.pl
- Version: 1.0, 2024-07-26

## snapsend.sh

### Description

snapsend.sh is a script for creating and sending ZFS snapshots. It supports both local and remote destinations, with options for recursion, compression, and buffering.

### Usage

```bash
./snapsend.sh [options] <local_datasets> <remote>
Options

    -m <prefix>: Custom prefix for the snapshot.
    -u <user>: SSH user for remote connection.
    -h <host>: Remote host (IP or hostname).
    -R: Recursion.
    -b: Use mbuffer.
    -z: Use compression.

E# Example Usage:
# Remote Backup: ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "192.168.28.8:hdd/kopie"
# Remote Synchronization: ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "192.168.28.8:"
# Local Backup: ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "hdd/kopie"
# Remote Backup with Compression and mbuffer: ./snapsend.sh -m "automated_hourly_" -R -z -b "hdd/tests,rpool/data/tests" "192.168.28.8:hdd/kopie"

## delsnaps.sh
### Description


delsnaps.sh is a script for deleting ZFS snapshots based on a specified pattern and age.
Usage

bash

./delsnaps.sh [-R] <datasets> <pattern> -y<years> -m<months> -w<weeks> -d<days> -h<hours>

Options

    -R: Recursion.
    -y <years>: Years.
    -m <months>: Months.
    -w <weeks>: Weeks.
	
	Usage examples:
# 1. Delete snapshots older than 1 year and 6 months for datasets "tank/data1" and "tank/data2" recursively:
#    ./delsnaps.sh -R "tank/data1,tank/data2" "backup-" -y1 -m6 -d0 -h0
# 2. Delete snapshots older than 2 years without recursion for dataset "tank/data3":
#    ./delsnaps.sh "tank/data3" "snapshot-" -y2 -m0 -d0 -h0


cron.txt
Description

The cron.txt file contains example cron jobs for automating the execution of snapsend.sh and delsnaps.sh.

MAILTO=""
SHELL=/bin/bash
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/root/skrypty:/root/scripts/zfs-snapshot-all

# Example Cron Jobs

# Hourly Snapshots
0 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
5 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:hdd/kopie" 2>>/root/scripts/cron.log

# Daily Snapshots
10 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
15 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:hdd/kopie" 2>>/root/scripts/cron.log
16 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" "rpool/ROOT/pve-1" "192.168.28.8:hdd/kopie/pve1" 2>>/root/scripts/cron.log

# Weekly Snapshots
20 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
25 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:hdd/kopie" 2>>/root/scripts/cron.log

# Monthly Snapshots
30 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -R -z -b "rpool/data" "192.168.28.8:" 2>>/root/scripts/cron.log
35 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0" "192.168.28.8:hdd/kopie" 2>>/root/scripts/cron.log

# Deleting Old Snapshots
40 * * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24 2>>/root/scripts/cron.log
46 0 * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30 2>>/root/scripts/cron.log
48 0 * * 0 /root/scripts/zfs-snapshot-all/delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4 2>>/root/scripts/cron.log
50 0 1 * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12 2>>/root/scripts/cron.log




