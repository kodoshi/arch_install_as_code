#!/usr/bin/env bash
set -Eeuo pipefail

# Function to converge storage configuration
# This script handles disk partitioning, LUKS encryption, BTRFS formatting, and subvolume creation.
# It attempts to be idempotent by checking if the device is already set up.
converge_storage() {
  local disk="$1"
  local part_efi="${disk}1"
  local part_root="${disk}2"
  # Handle NVMe naming convention (e.g., /dev/nvme0n1 -> /dev/nvme0n1p1)
  if [[ "$disk" == *"nvme"* ]]; then
    part_efi="${disk}p1"
    part_root="${disk}p2"
  fi

  echo ">>> Converging storage on $disk..."

  # Check if partitions exist
  if ! lsblk "$part_efi" >/dev/null 2>&1 || ! lsblk "$part_root" >/dev/null 2>&1; then
      echo "    Partitions not found. Partitioning $disk..."
      sgdisk -Z "$disk"
      sgdisk -n1:0:+1024M -t1:ef00 "$disk" # EFI Partition
      sgdisk -n2:0:0 -t2:8304 "$disk"      # Linux Root (x86-64) for Discoverable Partitions
      partprobe "$disk"
      sleep 2 # Wait for kernel to register partitions
  else
      echo "    Partitions already exist on $disk."
  fi

  # Check if LUKS is already open
  if [ -e /dev/mapper/cryptroot ]; then
      echo "    LUKS volume 'cryptroot' is already open."
  else
      # Check if it's a LUKS device
      if cryptsetup isLuks "$part_root"; then
          echo "    Opening existing LUKS volume..."
          # This will prompt for password
          cryptsetup open "$part_root" cryptroot
      else
          echo "    Formatting LUKS volume..."
          cryptsetup luksFormat \
            --type luks2 \
            --pbkdf argon2id \
            --pbkdf-memory 1048576 \
            --pbkdf-parallel 4 \
            --iter-time 4000 \
            "$part_root"
          cryptsetup open "$part_root" cryptroot
      fi
  fi

  # Check BTRFS
  if ! blkid /dev/mapper/cryptroot | grep -q "TYPE=\"btrfs\""; then
      echo "    Formatting BTRFS..."
      mkfs.btrfs /dev/mapper/cryptroot
  else
      echo "    BTRFS filesystem detected."
  fi

  # Mount root to create subvolumes
  if ! mountpoint -q /mnt; then
      mount /dev/mapper/cryptroot /mnt
  fi

  # Create subvolumes if they don't exist
  local subvols=(@ @home @srv @var @log @cache @tmp @snapshots)
  for sv in "${subvols[@]}"; do
    if [ ! -d "/mnt/$sv" ]; then
        echo "    Creating subvolume $sv..."
        btrfs subvolume create "/mnt/$sv"
    else
        echo "    Subvolume $sv exists."
    fi
  done

  # Unmount to remount with correct subvolumes
  umount /mnt

  # Mount @ (root)
  echo "    Mounting @ to /mnt..."
  mount -o subvol=@,compress=zstd,noatime /dev/mapper/cryptroot /mnt

  # Create mountpoints
  mkdir -p /mnt/{home,srv,var,efi,boot}

  # Mount other subvolumes
  echo "    Mounting subvolumes..."
  mount -o subvol=@home,compress=zstd,noatime /dev/mapper/cryptroot /mnt/home
  mount -o subvol=@srv,compress=zstd,noatime /dev/mapper/cryptroot /mnt/srv
  mount -o subvol=@var,compress=zstd,noatime /dev/mapper/cryptroot /mnt/var

  # Note: Source A suggests disabling CoW for /var, but BTRFS subvol mounting with nodatacow is tricky
  # if it's the same FS. Usually requires chattr +C on the directory before writing.
  # We'll stick to standard mounting for now.

  # Format and Mount EFI
  if ! blkid "$part_efi" | grep -q "TYPE=\"vfat\""; then
      echo "    Formatting EFI partition..."
      mkfs.vfat -F32 -n EFI "$part_efi"
  fi

  echo "    Mounting EFI to /mnt/efi..."
  mount "$part_efi" /mnt/efi
}
