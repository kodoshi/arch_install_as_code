#!/usr/bin/env bash
set -Eeuo pipefail

# Function to choose the target disk
# Interactive script to select a disk for installation.
# WARNING: This script asks for confirmation to WIPE the disk.
choose_target_disk() {
  mapfile -t DISKS < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')

  echo "Available disks:"
  for i in "${!DISKS[@]}"; do
    d="/dev/${DISKS[$i]}"
    echo "[$i] $d"
    lsblk -dno MODEL,SIZE "$d" | sed 's/^/    /'
    lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT,UUID "$d" | sed 's/^/    /'
  done

  read -rp "Select disk index to WIPE: " idx
  TARGET_DISK="/dev/${DISKS[$idx]}"

  echo "Selected: $TARGET_DISK"
  read -rp "Type '$TARGET_DISK' to confirm: " c1
  [[ "$c1" == "$TARGET_DISK" ]] || exit 1

  read -rp "Type WIPE-THIS-DISK to continue: " c2
  [[ "$c2" == "WIPE-THIS-DISK" ]] || exit 1
}
