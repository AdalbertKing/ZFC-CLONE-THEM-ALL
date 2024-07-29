 # Snapsend.sh, delsnaps.sh

 **Author:** Wojciech Król & ChatGPT-4o  
 **Version:** 1.65, 2024-07-28

 ## Overview

 `snapsend.sh` is a robust script designed for ZFS snapshot management, supporting various configurations for local and remote operations, including compression, buffering, and forceful full send in case of incremental send failure.

 ## Modes of Operation

 The script supports three distinct modes of operation:

 1. **Local Mode:** Transfers snapshots within the same server.
 2. **Remote Backup Mode:** Transfers snapshots to a remote backup server.
 3. **Remote Synchronization Mode:** Keeps datasets synchronized between local and remote servers.

 ## Script Options

 - `-m`: Custom snapshot prefix.
 - `-u`: Custom SSH user.
 - `-k`: SSH password.
 - `-p`: SSH port (default: 22).
 - `-R`: Recursion for datasets.
 - `-b`: Use mbuffer for buffering.
 - `-z`: Use gzip for compression.
 - `-f`: Force full send if incremental fails.
 - `-F`: Force full send immediately.
 - `-v`: Verbose level (1: minimal, 2: normal, 3: debug).

 ## Usage

 ```bash
 ./snapsend.sh [-m snapshot_prefix] [-u remote_user] [-k password] [-p remote_port] [-R] [-b] [-z] [-f] [-F] [-v verbose_level] local_datasets remote
 ```

 ## Examples

 ### Local Mode

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -z -b "rpool/data" "hdd/backups"
 ```

 This command creates and sends snapshots of `rpool/data` to `hdd/backups` with recursion, gzip compression, and buffering.

 ### Remote Synchronization Mode

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -F -u "root" -k "password" "rpool/data/vm-100-disk-0" "192.168.28.8:"
 ```

 This command keeps the dataset `rpool/data/vm-100-disk-0` synchronized between the local server and the remote server (192.168.28.8).

 ### Remote Backup Mode

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -F -u "root" -k "password" "rpool/data" "192.168.28.8:/backups"
 ```

 This command creates and sends snapshots of `rpool/data` and descendants to a remote server to `backups/rpool/data`.

 ### Example with Debugging and Without SSH Credentials

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -v 3 "rpool/data" "192.168.28.8:/backups"
 ```

 This command creates and sends snapshots of `rpool/data` to `192.168.28.8:/backups` with recursion and debug-level verbosity. Note that SSH keys must be exchanged between servers for passwordless login. For more information on setting up SSH key-based authentication, refer to this [guide](https://www.ssh.com/ssh/keygen/).

 ### Example with Force Incremental (-f)

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -f -u "root" -k "password" "rpool/data/vm-100-disk-0" "192.168.28.8:/backups"
 ```

 This command tries to send an incremental snapshot of `rpool/data/vm-100-disk-0` to `192.168.28.8:/backups`. If it fails, it forces a full send.

 ### Example without Force Incremental (-f)

 ```bash
 ./snapsend.sh -m "automated_hourly_" -R -u "root" -k "password" "rpool/data/vm-100-disk-0" "192.168.28.8:/backups"
 ```

 This command attempts to send an incremental snapshot of `rpool/data/vm-100-disk-0` to `192.168.28.8:/backups` without forcing a full send on failure.

 ## Warnings and Considerations

 ### Using -f and -F (Unconditional force to send full snapshot)

 Using `-f` (force incremental) in combination with `-R` (recursive) can lead to a full send for all child datasets if an issue occurs with one of them. This can result in long transfer times and high network usage. Use with caution.

 ### Scenario

 Imagine a Proxmox server with multiple large virtual machines. If an admin accidentally deletes the last snapshot for `rpool/data/vm-100-disk-0`, the target server will have one redundant snapshot. This will prevent an incremental ZFS send. Using the script with `./snapsend.sh -m "automated_hourly_" -R -f "rpool/data/vm-disks" "192.168.28.8:hdd/kopie"` will trigger a full ZFS send for all VMs from source to target, after performing `zfs destroy hdd/kopie/rpool/data/vm-disks`. This can lead to hours of network load and halt the transfer of other snapshots.

 # delsnaps.sh

 **Author:** Wojciech Król & ChatGPT-4  
 **Email:** lurk@lurk.com.pl  
 **Version:** 1.1, 2024-07-27

 ## Description

 This script automates the process of deleting old ZFS snapshots based on specified age criteria. It supports recursive operations for specified datasets.

 ## Usage

 ```bash
 ./delsnaps.sh [-R] <comma-separated list of datasets> <pattern> -y<years> -m<months> -w<weeks> -d<days> -h<hours>
 ```

 ## Options

 - `-R`: Recursively process child datasets.
 - `<comma-separated list of datasets>`: List of datasets to process, separated by commas.
 - `<pattern>`: Pattern to match snapshots for deletion.
 - `-y <years>`: Specify the age in years.
 - `-m <months>`: Specify the age in months.
 - `-w <weeks>`: Specify the age in weeks.
 - `-d <days>`: Specify the age in days.
 - `-h <hours>`: Specify the age in hours.

 ## Examples

 ### Delete Hourly Snapshots Older Than 24 Hours

 ```bash
 ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_hourly" -h24
 ```

 This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_hourly` that are older than 24 hours.

 ### Delete Daily Snapshots Older Than 30 Days

 ```bash
 ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_daily" -d30
 ```

 This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_daily` that are older than 30 days.

 ### Delete Weekly Snapshots Older Than 4 Weeks

 ```bash
 ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_weekly" -w4
 ```

 This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_weekly` that are older than 4 weeks.

 ### Delete Monthly Snapshots Older Than 12 Months

 ```bash
 ./delsnaps.sh -R "hdd/vm-disks,rpool/data" "automated_monthly" -m12
 ```

 This command will recursively delete snapshots from the datasets `hdd/vm-disks` and `rpool/data` with the prefix `automated_monthly` that are older than 12 months.

 ## Contact

 For any further questions or issues, please contact the author at lurk@lurk.com.pl.

 ## Crontab Example

 To automate the execution of these scripts, you can add entries to your crontab file. For example, to run `snapsend.sh` every hour and `delsnaps.sh` every day, you can add the following lines to your crontab file:

 ```bash
 MAILTO=""
 SHELL=/bin/bash
 PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin:/root/skrypty:/root/scripts/zfs-snapshot-all

 # Hourly Snapshots
 0 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -R -z -b "rpool/data" "192.168.28.8:" 2/root/scripts/cron.log
 5 * * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_hourly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0,hdd/vm-disks> 2/root/scripts/cron.log

 # Daily Snapshots
 10 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -R -z -b "rpool/data" "192.168.28.8:" 2/root/scripts/cron.log
 15 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0,hdd/vm-disks> 2/root/scripts/cron.log
 16 0 * * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_daily_" "rpool/ROOT/pve-1" "192.168.28.8:hdd/kopie/pve1" 2/root/scripts/cron.log

 # Weekly Snapshots
 20 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -R -z -b "rpool/data" "192.168.28.8:" 2/root/scripts/cron.log
 25 0 * * 0 /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_weekly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0,hdd/vm-disk> 2/root/scripts/cron.log

 # Monthly Snapshots
 30 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -R -z -b "rpool/data" "192.168.28.8:" 2/root/scripts/cron.log
 35 0 1 * * /root/scripts/zfs-snapshot-all/snapsend.sh -m "automated_monthly_" -z -b "hdd/vm-disks/subvol-101-disk-0,hdd/vm-disks/subvol-101-disk-1,hdd/vm-disks/subvol-107-disk-0,hdd/vm-disks> 2/root/scripts/cron.log

 # Snapshot Deletion
 40 * * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_hourly -h24 2/root/scripts/cron.log
 46 0 * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_daily -d30 2/root/scripts/cron.log
 48 0 * * 0 /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_weekly -w4 2/root/scripts/cron.log
 50 0 1 * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks,rpool/data automated_monthly -m12 2/root/scripts/cron.log
 42 * * * * /root/scripts/zfs-snapshot-all/delsnaps.sh -R hdd/vm-disks zincrsend_zincrsend -d31 2/root/scripts/cron.log
 ```

 ## Summary

 This documentation provides an overview of the `snapsend.sh` and `delsnaps.sh` scripts, detailing their usage, options, and examples. These scripts facilitate efficient ZFS snapshot management, including local and remote backup and synchronization. By leveraging options like recursion, compression, and verbose logging, administrators can tailor the scripts to their specific needs. Caution is advised when using forceful send options to avoid unintended consequences, such as excessive network load or data transfer times. The inclusion of crontab examples demonstrates how to automate these processes, ensuring regular and reliable snapshot management.
