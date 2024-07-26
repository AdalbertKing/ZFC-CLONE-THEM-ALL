#!/bin/bash

# Author: Wojciech KrĂłl & Chat-GPT 4o
# Email: lurk@lurk.com.pl
# Ver: 1.0 from 2024-07-26

# Description:
# This script automates the process of creating and sending ZFS snapshots to a remote server or local dataset.

# Usage examples:
# 1. Remote backup:
#    ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "192.168.28.8:hdd/kopie"
# 2. Remote synchronization:
#    ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "192.168.28.8:"
# 3. Local backup:
#    ./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "hdd/kopie"
# 4. Remote backup with compression and mbuffer:
#    ./snapsend.sh -m "automated_hourly_" -R -z -b "hdd/tests,rpool/data/tests" "192.168.28.8:hdd/kopie"

# Options:
# -m <snapshot_prefix> : Custom prefix for snapshots.
# -u <remote_user>     : Custom SSH user.
# -R                   : Enable recursion.
# -b                   : Use mbuffer for data transfer.
# -z                   : Enable compression during transfer.

# PID file to monitor simultaneous script execution
PIDFILE="/var/run/snapsend.pid"
LOGFILE="/var/log/snapsend.log"

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

cleanup() {
  rm -f "$PIDFILE"
  exit 0
}

trap cleanup INT TERM EXIT

if [ -e "$PIDFILE" ]; then
  log "Snapsend is already running."
  exit 1
fi
echo $$ > "$PIDFILE"

snapshot_prefix=""
remote_user="root"
recursive=false
use_mbuffer=false
compression=false

# Parsing options
while getopts "m:u:Rbz" opt; do
  case $opt in
    m)
      snapshot_prefix=$OPTARG  # Custom snapshot prefix
      ;;
    u)
      remote_user=$OPTARG  # Custom SSH user
      ;;
    R)
      recursive=true  # Recursion
      ;;
    b)
      use_mbuffer=true  # Use mbuffer
      ;;
    z)
      compression=true  # Use compression
      ;;
    \?)
      log "Invalid option: -$OPTARG"
      rm -f "$PIDFILE"
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Arguments
local_datasets="$1"
remote="$2"

# Validate input arguments
if [[ -z "$local_datasets" || -z "$remote" ]]; then
  log "Usage: $0 [-m snapshot_prefix] [-u remote_user] [-R] [-b] [-z] local_datasets remote"
  rm -f "$PIDFILE"
  exit 1
fi

IFS=',' read -r -a datasets <<< "$local_datasets"
remote_server="${remote%%:*}"
remote_path="${remote#*:}"

# Check if the operation is local
is_local=false
if [[ "$remote_server" == "$remote" ]]; then
  is_local=true
  remote_server=""
  remote_path="$remote"
fi

# Remove trailing slash
remove_trailing_slash() {
  echo "${1%/}"
}

# Main loop to process datasets
for dataset in "${datasets[@]}"; do
  local_dataset=$(remove_trailing_slash "$dataset")

  # Check if the dataset exists on the source
  if ! zfs list "$local_dataset" &>/dev/null; then
    log "Dataset does not exist: $local_dataset"
    continue
  fi

  # Set recursion options
  snapshot_opts=""
  send_opts=""
  if [ "$recursive" = true ]; then
    snapshot_opts="-r"
    send_opts="-R"
  fi

  # Check and create remote dataset path
  if [ -n "$remote_path" ]; then
    remote_dataset_path="${remote_path}/${local_dataset}"
  else
    remote_dataset_path="${local_dataset}"
  fi
  remote_dataset_path=$(remove_trailing_slash "$remote_dataset_path")

  # Ensure the remote dataset exists
  if [ "$is_local" = true ]; then
    log "Ensuring local dataset exists: $remote_dataset_path"
    zfs list "$remote_dataset_path" 2>/dev/null || zfs create -p "$remote_dataset_path"
  else
    log "Ensuring remote dataset exists: $remote_dataset_path"
    ssh "$remote_user@$remote_server" "zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path"
  fi

  # Create local snapshot
  timestamp=$(date +%F_%H-%M-%S)
  local_snapshot="${local_dataset}@${snapshot_prefix}${timestamp}"
  log "Creating local snapshot: $local_snapshot"
  log "ZFS Command: zfs snapshot $snapshot_opts $local_snapshot"
  if ! zfs snapshot $snapshot_opts "$local_snapshot"; then
    log "Failed to create local snapshot: $local_snapshot"
    continue
  fi

  # Find the latest remote snapshot
  log "Finding latest remote snapshot in $remote_dataset_path"
  if [ "$is_local" = true ]; then
    latest_remote_snapshot=$(zfs list -H -o name,creation -p -t snapshot -r "$remote_dataset_path" | grep "^$remote_dataset_path@" | sort -n -k 2 | tail -1 | awk '{print $1}')
  else
    latest_remote_snapshot=$(ssh "$remote_user@$remote_server" "zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'")
  fi

  if [ -n "$latest_remote_snapshot" ]; then
    log "Latest remote snapshot found: $latest_remote_snapshot"
    log "Performing incremental send from $latest_remote_snapshot to $local_snapshot"
    if [ "$is_local" = true ]; then
      log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | zfs recv -F $remote_dataset_path"
      if ! zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | zfs recv -F "$remote_dataset_path"; then
        log "Failed to send incremental snapshot $local_snapshot to $remote_dataset_path"
        continue
      fi
    else
      if $use_mbuffer; then
        if $compression; then
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | gzip | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"; then
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        else
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"; then
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        fi
      else
        if $compression; then
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip | ssh $remote_user@$remote_server 'gunzip | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | gzip | ssh "$remote_user@$remote_server" "gunzip | zfs recv -F $remote_dataset_path"; then
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        else
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | ssh $remote_user@$remote_server 'zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | ssh "$remote_user@$remote_server" "zfs recv -F $remote_dataset_path"; then
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        fi
      fi
    fi
  else
    log "No remote snapshot found, performing full send of $local_snapshot"
    if [ "$is_local" = true ]; then
      log "ZFS Command: zfs send $send_opts $local_snapshot | zfs recv -F $remote_dataset_path"
      if ! zfs send $send_opts "$local_snapshot" | zfs recv -F "$remote_dataset_path"; then
        log "Failed to send full snapshot $local_snapshot to $remote_dataset_path"
        continue
      fi
    else
      if $use_mbuffer; then
        if $compression; then
          log "ZFS Command: zfs send $send_opts $local_snapshot | gzip | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts "$local_snapshot" | gzip | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"; then
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        else
          log "ZFS Command: zfs send $send_opts $local_snapshot | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts "$local_snapshot" | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"; then
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        fi
      else
        if $compression; then
          log "ZFS Command: zfs send $send_opts $local_snapshot | gzip | ssh $remote_user@$remote_server 'gunzip | zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts "$local_snapshot" | gzip | ssh "$remote_user@$remote_server" "gunzip | zfs recv -F $remote_dataset_path"; then
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        else
          log "ZFS Command: zfs send $send_opts $local_snapshot | ssh $remote_user@$remote_server 'zfs recv -F $remote_dataset_path'"
          if ! zfs send $send_opts "$local_snapshot" | ssh "$remote_user@$remote_server" "zfs recv -F $remote_dataset_path"; then
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
            continue
          fi
        fi
      fi
    fi
  fi

  log "Snapshot sent successfully: $local_snapshot to $remote_server:$remote_dataset_path"
done

rm -f "$PIDFILE"
exit 0

