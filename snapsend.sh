#!/bin/bash

# Author: Wojciech Król & ChatGPT-4o
# Email: lurk@lurk.com.pl
# Version: 1.65, 2024-07-28

# This script is a powerful tool for ZFS snapshot management, including options for remote and local operations,
# compression, buffering, and forceful full send in case of incremental send failure.

# WARNING: Using -f in combination with -R can lead to full send for all child datasets if any issue occurs in one of them.
# This can result in long transfer times and high network usage. Use with caution.

# Required utilities: sshpass (for password-based SSH login), mbuffer (for buffering), gzip (for compression)

PIDFILE="/var/run/snapsend.pid"
LOGFILE="/var/log/snapsend.log"
VERBOSE_LEVEL=1  # Default verbose level

log() {
  if [ $1 -le $VERBOSE_LEVEL ]; then
    shift
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
  fi
}

if [ -e "$PIDFILE" ]; then
  log 1 "Snapsend is already running."
  exit 1
fi
echo $$ > "$PIDFILE"

snapshot_prefix="default_"
remote_user="root"
remote_password=""
remote_port=22  # Default SSH port
recursive=false
use_mbuffer=false
compression=false
force_incremental=false
force_full=false

trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT

# Parsing options
while getopts "m:u:k:p:RbzfFv:" opt; do
  case $opt in
    m)
      snapshot_prefix=$OPTARG  # Custom snapshot prefix
      ;;
    u)
      remote_user=$OPTARG  # Custom SSH user
      ;;
    k)
      remote_password=$OPTARG  # SSH password
      ;;
    p)
      remote_port=$OPTARG  # SSH port
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
    v)
      VERBOSE_LEVEL=$OPTARG  # Set verbose level
      ;;
    \?)
      log 1 "Invalid option: -$OPTARG"
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
  log 1 "Usage: $0 [-m snapshot_prefix] [-u remote_user] [-k remote_password] [-p remote_port] [-R] [-b] [-z] [-f] [-F] [-v verbose_level] local_datasets remote"
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
  log 3 "Connecting to remote server with password: sshpass -p '******' ssh -o StrictHostKeyChecking=no -p $remote_port $remote_user@$remote_server \"$*\""
  sshpass -p "$remote_password" ssh -o StrictHostKeyChecking=no -p "$remote_port" "$remote_user@$remote_server" "$@"
}

# Function to delete all snapshots in the remote dataset
delete_remote_snapshots() {
  local remote_dataset="$1"
  if [ -n "$remote_password" ]; then
    ssh_with_password "zfs list -H -o name -t snapshot -r $remote_dataset | xargs -n1 zfs destroy"
  else
    ssh -p "$remote_port" "$remote_user@$remote_server" "zfs list -H -o name -t snapshot -r $remote_dataset | xargs -n1 zfs destroy"
  fi
}

# Execute zfs send and receive commands
execute_zfs_send_receive() {
  local zfs_send_command="$1"
  local ssh_recv_command="$2"
  if [ "$is_local" = true ]; then
    log 3 "ZFS Command: $zfs_send_command | $ssh_recv_command"
    if eval "$zfs_send_command | $ssh_recv_command"; then
      incremental_success=true
    else
      log 1 "Failed to send snapshot $local_snapshot to $remote_dataset_path"
    fi
  else
    log 3 "ZFS Command: $zfs_send_command | ssh -p $remote_port $remote_user@$remote_server '$ssh_recv_command'"
    if eval "$zfs_send_command | ssh -p $remote_port $remote_user@$remote_server '$ssh_recv_command'"; then
      incremental_success=true
    else
      log 1 "Failed to send snapshot $local_snapshot to $remote_server:$remote_dataset_path"
    fi
  fi
}

# Main dataset processing loop
for dataset in "${datasets[@]}"; do
  local_dataset=$(remove_trailing_slash "$dataset")

  # Check if source dataset exists
  if ! zfs list "$local_dataset" &>/dev/null; then
    log 1 "Dataset does not exist: $local_dataset"
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
    log 2 "Ensuring local dataset exists: $remote_dataset_path"
    zfs list "$remote_dataset_path" 2>/dev/null || zfs create -p "$remote_dataset_path"
  else
    log 2 "Ensuring remote dataset exists: $remote_dataset_path"
    if [ -n "$remote_password" ]; then
      ssh_with_password "zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path"
    else
      log 3 "SSH Command: ssh -p $remote_port $remote_user@$remote_server \"zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path\""
      ssh -p "$remote_port" "$remote_user@$remote_server" "zfs list $remote_dataset_path 2>/dev/null || zfs create -p $remote_dataset_path"
    fi
  fi

  # Create local snapshot
  timestamp=$(date +%F_%H-%M-%S)
  local_snapshot="${local_dataset}@${snapshot_prefix}${timestamp}"
  log 2 "Creating local snapshot: $local_snapshot"
  log 3 "ZFS Command: zfs snapshot $snapshot_opts $local_snapshot"
  if ! zfs snapshot $snapshot_opts "$local_snapshot"; then
    log 1 "Failed to create local snapshot: $local_snapshot"
    continue
  fi

  # Handle force full send option
  if [ "$force_full" = true ]; then
    log 2 "Force full send enabled. Deleting all remote snapshots in $remote_dataset_path"
    if [ "$is_local" = true ]; then
      zfs list -H -o name -t snapshot -r "$remote_dataset_path" | xargs -n1 zfs destroy
    else
      delete_remote_snapshots "$remote_dataset_path"
    fi
    latest_remote_snapshot=""
  else
    # Find latest remote snapshot
    log 2 "Finding latest remote snapshot in $remote_dataset_path"
    if [ "$is_local" = true ]; then
      latest_remote_snapshot=$(zfs list -H -o name,creation -p -t snapshot -r "$remote_dataset_path" | grep "^$remote_dataset_path@" | sort -n -k 2 | tail -1 | awk '{print $1}')
    else
      if [ -n "$remote_password" ]; then
        log 3 "SSH Command: ssh_with_password \"$remote_user@$remote_server\" \"zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'\""
        latest_remote_snapshot=$(ssh_with_password "zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'")
      else
        log 3 "SSH Command: ssh -p $remote_port $remote_user@$remote_server \"zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'\""
        latest_remote_snapshot=$(ssh -p "$remote_port" "$remote_user@$remote_server" "zfs list -H -o name,creation -p -t snapshot -r $remote_dataset_path | grep '^$remote_dataset_path@' | sort -n -k 2 | tail -1 | awk '{print \$1}'")
      fi
    fi
  fi

  incremental_success=false

  if [ -n "$latest_remote_snapshot" ]; then
    log 2 "Latest remote snapshot found: $latest_remote_snapshot"
    log 2 "Performing incremental send from $latest_remote_snapshot to $local_snapshot"
    if [ "$is_local" = true ]; then
      zfs_send_command="zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot"
      ssh_recv_command="zfs recv -F $remote_dataset_path"
      execute_zfs_send_receive "$zfs_send_command" "$ssh_recv_command"
    else
      if $use_mbuffer; then
        if $compression; then
          zfs_send_command="zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip | mbuffer -s 128k -m 1G"
          ssh_recv_command="mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"
        else
          zfs_send_command="zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | mbuffer -s 128k -m 1G"
          ssh_recv_command="mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"
        fi
      else
        if $compression; then
          zfs_send_command="zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot | gzip"
          ssh_recv_command="gunzip | zfs recv -F $remote_dataset_path"
        else
          zfs_send_command="zfs send $send_opts -I ${latest_remote_snapshot##*@} $local_snapshot"
          ssh_recv_command="zfs recv -F $remote_dataset_path"
        fi
      fi
      execute_zfs_send_receive "$zfs_send_command" "$ssh_recv_command"
    fi
  else
    log 2 "No remote snapshot found, performing full send of $local_snapshot"
    if [ "$is_local" = true ]; then
      zfs_send_command="zfs send $send_opts $local_snapshot"
      ssh_recv_command="zfs recv -F $remote_dataset_path"
      execute_zfs_send_receive "$zfs_send_command" "$ssh_recv_command"
    else
      if $use_mbuffer; then
        if $compression; then
          zfs_send_command="zfs send $send_opts $local_snapshot | gzip | mbuffer -s 128k -m 1G"
          ssh_recv_command="mbuffer -s 128k -m 1G | gunzip | zfs recv -F $remote_dataset_path"
        else
          zfs_send_command="zfs send $send_opts $local_snapshot | mbuffer -s 128k -m 1G"
          ssh_recv_command="mbuffer -s 128k -m 1G | zfs recv -F $remote_dataset_path"
        fi
      else
        if $compression; then
          zfs_send_command="zfs send $send_opts $local_snapshot | gzip"
          ssh_recv_command="gunzip | zfs recv -F $remote_dataset_path"
        else
          zfs_send_command="zfs send $send_opts $local_snapshot"
          ssh_recv_command="zfs recv -F $remote_dataset_path"
        fi
      fi
      execute_zfs_send_receive "$zfs_send_command" "$ssh_recv_command"
    fi
  fi

  if [ "$incremental_success" = false ] && [ "$force_incremental" = true ]; then
    log 1 "Incremental send failed and force incremental option is enabled. Performing full send."
    if [ "$is_local" = true ]; then
      zfs list -H -o name -t snapshot -r "$remote_dataset_path" | xargs -n1 zfs destroy
    else
      delete_remote_snapshots "$remote_dataset_path"
    fi
    log 2 "ZFS Command: zfs send $send_opts $local_snapshot | zfs recv -F $remote_dataset_path"
    if ! zfs send $send_opts "$local_snapshot" | zfs recv -F "$remote_dataset_path"; then
      log 1 "Failed to send full snapshot $local_snapshot to $remote_dataset_path"
      continue
    fi
  fi

  log 1 "Snapshot sent successfully: $local_snapshot to $remote_server:$remote_dataset_path"
done

rm -f "$PIDFILE"
exit 0
