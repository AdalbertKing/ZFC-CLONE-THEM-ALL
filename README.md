
### Plik `README.md` (angielski)

```markdown
# ZFS-snaps-remote-clone-synchro-and-delete

## Description

SnapSend and DelSnaps are scripts for automating the creation and deletion of ZFS snapshots.

### SnapSend Features

- Automatic snapshot creation
- Sending snapshots to remote servers or local datasets
- Support for incremental and full transfers
- Optional support for compression and mbuffer

### DelSnaps Features

- Deleting old snapshots based on specified time criteria
- Support for recursive operations

### SnapSend Options

- `-m <snapshot_prefix>`: Custom prefix for snapshots.
- `-u <remote_user>`: Custom SSH user.
- `-R`: Enable recursion.
- `-b`: Use mbuffer for data transfer.
- `-z`: Enable compression during transfer.

### Example SnapSend Usages

#### Remote Backup
```bash
./snapsend.sh -m "automated_hourly_" -R "hdd/tests,rpool/data/tests" "192.168.28.8:hdd/kopie"
