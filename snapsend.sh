#!/bin/bash

# Author: Wojciech Król & ChatGPT-4o
# Email: lurk@lurk.com.pl
# Version: 1.3, 2024-07-27

# This script is a powerful tool for ZFS snapshot management, including options for remote and local operations, 
# compression, buffering, and forceful full send in case of incremental send failure.

# WARNING: Using -f in combination with -R can lead to full send for all child datasets if any issue occurs in one of them.
# This can result in long transfer times and high network usage. Use with caution.

# Required utilities: sshpass (for password-based SSH login), mbuffer (for buffering), gzip (for compression)

# Examples:
# Local send:
# ./snapsend02.sh -m "snapshot_" "tank/dataset" "tank/backup"
# Remote send with SSH password:
# ./snapsend02.sh -m "snapshot_" -u "root" -p "password" "tank/dataset" "remote_server:tank/backup"
# Recursive send with mbuffer and compression:
# ./snapsend02.sh -m "snapshot_" -R -b -z "tank/dataset" "remote_server:tank/backup"
# Force full send if incremental fails:
# ./snapsend02.sh -m "snapshot_" -f "tank/dataset" "remote_server:tank/backup"
# Immediate full send:
# ./snapsend02.sh -m "snapshot_" -F "tank/dataset" "remote_server:tank/backup"

PIDFILE="/var/run/snapsend.pid"
LOGFILE="/var/log/snapsend.log"

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

if [ -e "$PIDFILE" ]; then
  log "Snapsend is already running."
  exit 1
fi
echo $$ > "$PIDFILE"

snapshot_prefix="default_"
remote_user="root"
remote_password=""
recursive=false
use_mbuffer=false
compression=false
force_incremental=false
force_full=false

trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT

# Parsing options
while getopts "m:u:p:RbzfF" opt; do
  case $opt in
    m)
      snapshot_prefix=$OPTARG  # Custom snapshot prefix
      ;;
    u)
      remote_user=$OPTARG  # Custom SSH user
      ;;
    p)
      remote_password=$OPTARG  # SSH password
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
    f)
      force_incremental=true  # Force full send if incremental fails
      ;;
    F)
      force_full=true  # Force full send immediately
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
  log "Usage: $0 [-m snapshot_prefix] [-u remote_user] [-p remote_password] [-R] [-b] [-z] [-f] [-F] local_datasets remote"
  rm -f "$PIDFILE"
  exit 1
fi

IFS=',' read -r -a datasets <<< "$local_datasets"
remote_server="${remote%%:*}"
remote_path="${remote#*:}"

# Check if operation is local
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

# SSH with password
ssh_with_password() {
  log "Connecting to remote server with password: sshpass -p $remote_password ssh -o StrictHostKeyChecking=no $remote_user@$remote_server \"$*\""
  sshpass -p "$remote_password" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_server" "$@"
}

# Function to delete all snapshots in the remote dataset
delete_remote_snapshots() {
  local remote_dataset="$1"
  if [ -n "$remote_password" ]; then
    ssh_with_password "zfs list -H -o name -t snapshot -r $remote_dataset | xargs -n1 zfs destroy"
  else
    ssh "$remote_user@$remote_server" "zfs list -H -o name -t snapshot -r $remote_dataset | xargs -n1 zfs destroy"
  fi
}

# Main dataset processing loop
for dataset in "${datasets[@]}"; do
  local_dataset=$(remove_trailing_slash "$dataset")

  # Check if source dataset exists
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

  # Build remote dataset path
  if [ -n "$remote_path" ]; then
    remote_dataset_path="${remote_path}/${local_dataset}"
  else
    remote_dataset_path="${local_dataset}"
  fi
  remote_dataset_path=$(remove_trailing_slash "$remote_dataset_path")

  # Ensure remote dataset exists
  if [ "$is_local" = true ]; then
    log "Ensuring local dataset exists: $remote_dataset_path"
    zfs list "$remote_dataset_path" 2>/dev/null || zfs create -p "$remote_dataset_path"
  else
    log "Ensuring remote dataset exists: $remote_dataset_path"
    if [ -n "$remote_password" ]; then
      ssh_with_password "zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path"
    else
      log "SSH Command: ssh $remote_user@$remote_server \"zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path\""
      ssh "$remote_user@$remote_server" "zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path"
    fi
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

  # Handle force full send option
  if [ "$force_full" = true ]; then
    log "Force full send enabled. Deleting all remote snapshots in $remote_dataset_path"
    delete_remote_snapshots "$remote_dataset_path"
    latest_remote_snapshot=""
  else
    # Find latest remote snapshot
    log "Finding latest remote snapshot in $remote_dataset_path"
    if [ "$is_local" = true ]; then
      latest_remote_snapshot=$(zfs list -H -o name,creation -p -t snapshot -r "$remote_dataset_path" | grep "^$remote_dataset_path@" | sort -n -k 2 | tail -1 | awk '{print $1}')
    else
      if [ -n "$remote_password" ]; then
        log "SSH Command: ssh_with_password \"$remote_user@$remote_server\" \"zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'\""
        latest_remote_snapshot=$(ssh_with_password "zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'")
      else
        log "SSH Command: ssh $remote_user@$remote_server \"zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'\""
        latest_remote_snapshot=$(ssh "$remote_user@$remote_server" "zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'")
      fi
    fi
  fi

  incremental_success=false

  if [ -n "$latest_remote_snapshot" ]; then
    log "Latest remote snapshot found: $latest_remote_snapshot"
    log "Performing incremental send from $latest_remote_snapshot to $local_snapshot"
    if [ "$is_local" = true ]; then
      log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | zfs recv -F $remote_dataset_path"
      if zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | zfs recv -F "$remote_dataset_path"; then
        incremental_success=true
      else
        log "Failed to send incremental snapshot $local_snapshot to $remote_dataset_path"
      fi
    else
      if $use_mbuffer; then
        if $compression; then
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | gzip | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        else
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        fi
      else
        if $compression; then
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip | ssh $remote_user@$remote_server 'gunzip | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | gzip | ssh "$remote_user@$remote_server" "gunzip | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        else
          log "ZFS Command: zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | ssh $remote_user@$remote_server 'zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts -I "${latest_remote_snapshot##*@}" "$local_snapshot" | ssh "$remote_user@$remote_server" "zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send incremental snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        fi
      fi
    fi
  else
    log "No remote snapshot found, performing full send of $local_snapshot"
    if [ "$is_local" = true ]; then
      log "ZFS Command: zfs send $send_opts $local_snapshot | zfs recv -F $remote_dataset_path"
      if zfs send $send_opts "$local_snapshot" | zfs recv -F "$remote_dataset_path"; then
        incremental_success=true
      else
        log "Failed to send full snapshot $local_snapshot to $remote_dataset_path"
      fi
    else
      if $use_mbuffer; then
        if $compression; then
          log "ZFS Command: zfs send $send_opts $local_snapshot | gzip | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts "$local_snapshot" | gzip | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        else
          log "ZFS Command: zfs send $send_opts $local_snapshot | mbuffer -s 128k -m 1G | ssh $remote_user@$remote_server 'mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts "$local_snapshot" | mbuffer -s 128k -m 1G | ssh "$remote_user@$remote_server" "mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        fi
      else
        if $compression; then
          log "ZFS Command: zfs send $send_opts $local_snapshot | gzip | ssh $remote_user@$remote_server 'gunzip | zfs recv -F $remote_dataset_path'"
          if zfs send $send_opts "$local_snapshot" | gzip | ssh "$remote_user@$remote_server" "gunzip | zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        else
          log "ZFS Command: zfs send $local_snapshot | ssh $remote_user@$remote_server 'zfs recv -F $remote_dataset_path'"
          if zfs send "$local_snapshot" | ssh "$remote_user@$remote_server" "zfs recv -F $remote_dataset_path"; then
            incremental_success=true
          else
            log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
          fi
        fi
      fi
    fi
  fi

  if [ "$incremental_success" = false ] && [ "$force_incremental" = true ]; then
    log "Incremental send failed and force incremental option is enabled. Performing full send."
    delete_remote_snapshots "$remote_dataset_path"
    log "ZFS Command: zfs send $send_opts $local_snapshot | ssh $remote_user@$remote_server 'zfs recv -F $remote_dataset_path'"
    if ! zfs send "$local_snapshot" | ssh "$remote_user@$remote_server" "zfs recv -F $remote_dataset_path"; then
      log "Failed to send full snapshot $local_snapshot to $remote_server:$remote_dataset_path"
      continue
    fi
  fi

  log "Snapshot sent successfully: $local_snapshot to $remote_server:$remote_dataset_path"
done

rm -f "$PIDFILE"
exit 0
