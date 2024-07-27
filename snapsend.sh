#!/bin/bash

# Author: Wojciech Król & ChatGPT-4o
# Email: lurk@lurk.com.pl
# Version: 1.1, 2024-07-27

# Description:
# This script automates the process of creating and sending ZFS snapshots. 
# It supports both local and remote destinations, with options for recursion, 
# compression, and buffering. 

# Usage:
# ./snapsend.sh [options] <local_datasets> <remote>

# Options:
# -m <snapshot_prefix>       Specify a custom prefix for snapshots.
# -u <remote_user>           Specify the SSH user for remote operations.
# -p <remote_password>       Specify the SSH password for remote operations.
# -R                         Enable recursive operation.
# -b                         Use mbuffer for buffering.
# -z                         Enable compression with gzip.
# -f                         Force full send if incremental send fails.
# -F                         Always perform a full send.

# Examples:

# Local Backup:
# ./snapsend.sh -m "automated_hourly_" "rpool/data" "local_backup_path"

# Remote Backup:
# ./snapsend.sh -m "automated_hourly_" -u "root" -p "password" -b -z "rpool/data" "192.168.28.8:remote_backup_path"

# Remote Sync:
# ./snapsend.sh -m "automated_hourly_" -R -u "root" -p "password" -F "rpool/data" "192.168.28.8:remote_backup_path"

# The script continues below with actual implementation...

# Plik PID do monitorowania jednoczesnego uruchomienia skryptu
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

trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT

# Parsing opcji
while getopts "m:u:p:RbzfF" opt; do
  case $opt in
    m)
      snapshot_prefix=$OPTARG  # Niestandardowy prefix snapshotu
      ;;
    u)
      remote_user=$OPTARG  # Niestandardowy uĹĽytkownik SSH
      ;;
    p)
      remote_password=$OPTARG  # HasĹ‚o SSH
      ;;
    R)
      recursive=true  # Rekurencja
      ;;
    b)
      use_mbuffer=true  # UĹĽycie mbuffer
      ;;
    z)
      compression=true  # UĹĽycie kompresji
      ;;
    f)
      force_full_send=true  # Force full send if incremental send fails
      ;;
    F)
      always_full_send=true  # Always perform a full send
      ;;
    \?)
      log "Invalid option: -$OPTARG"
      rm -f "$PIDFILE"
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Argumenty
local_datasets="$1"
remote="$2"

# Walidacja argumentĂłw wejĹ›ciowych
if [[ -z "$local_datasets" || -z "$remote" ]]; then
  log "Usage: $0 [-m snapshot_prefix] [-u remote_user] [-p remote_password] [-R] [-b] [-z] [-f] [-F] local_datasets remote"
  rm -f "$PIDFILE"
  exit 1
fi

IFS=',' read -r -a datasets <<< "$local_datasets"
remote_server="${remote%%:*}"
remote_path="${remote#*:}"

# Sprawdzenie, czy operacja jest lokalna
is_local=false
if [[ "$remote_server" == "$remote" ]]; then
  is_local=true
  remote_server=""
  remote_path="$remote"
fi

# Funkcja do usuwania koĹ„cowego znaku "/"
remove_trailing_slash() {
  echo "${1%/}"
}

# Funkcja do logowania siÄ™ na zdalny serwer z uĹĽyciem hasĹ‚a
ssh_with_password() {
  log "Connecting to remote server with password: sshpass -p $remote_password ssh -o StrictHostKeyChecking=no $remote_user@$remote_server \"$*\""
  sshpass -p "$remote_password" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_server" "$@"
}

# GĹ‚Ăłwna pÄ™tla przetwarzajÄ…ca dataset
for dataset in "${datasets[@]}"; do
  local_dataset=$(remove_trailing_slash "$dataset")

  # Sprawdzenie, czy dataset istnieje po stronie source
  if ! zfs list "$local_dataset" &>/dev/null; then
    log "Dataset does not exist: $local_dataset"
    continue
  fi

  # Ustawienie opcji rekurencji
  snapshot_opts=""
  send_opts=""
  if [ "$recursive" = true ]; then
    snapshot_opts="-r"
    send_opts="-R"
  fi

  # Sprawdzanie i tworzenie zdalnej Ĺ›cieĹĽki datasetu
  if [ -n "$remote_path" ]; then
    remote_dataset_path="${remote_path}/${local_dataset}"
  else
    remote_dataset_path="${local_dataset}"
  fi
  remote_dataset_path=$(remove_trailing_slash "$remote_dataset_path")

  # Zapewnienie istnienia zdalnego datasetu
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

  # Tworzenie lokalnego snapshotu
  timestamp=$(date +%F_%H-%M-%S)
  local_snapshot="${local_dataset}@${snapshot_prefix}${timestamp}"
  log "Creating local snapshot: $local_snapshot"
  log "ZFS Command: zfs snapshot $snapshot_opts $local_snapshot"
  if ! zfs snapshot $snapshot_opts "$local_snapshot"; then
    log "Failed to create local snapshot: $local_snapshot"
    continue
  fi

  # Wyszukiwanie ostatniego zdalnego snapshotu
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
