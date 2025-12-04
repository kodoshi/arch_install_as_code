#!/usr/bin/env bash
set -Eeuo pipefail

# Arch OS as Code Installer / Converger
# This script orchestrates the installation and configuration of Arch Linux.
# It is designed to be idempotent and can be run multiple times to converge the system state.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source all convergence scripts
source "$SCRIPT_DIR/choose_disk.sh"
source "$SCRIPT_DIR/converge_storage.sh"
source "$SCRIPT_DIR/converge_packages.sh"
source "$SCRIPT_DIR/converge_gpu.sh"
source "$SCRIPT_DIR/converge_mkinitcpio.sh"
source "$SCRIPT_DIR/converge_boot.sh"

# Function to ask for confirmation
confirm_step() {
    local step_name="$1"
    local description="$2"

    echo ""
    echo "================================================================================"
    echo "STEP: $step_name"
    echo "--------------------------------------------------------------------------------"
    echo "$description"
    echo "================================================================================"
    echo ""

    while true; do
        read -rp "Do you want to proceed with this step? (yes/no): " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "Skipping $step_name..."; return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
    return 0
}

echo "=== Arch OS as Code installer ==="

# Check for required tools
if ! command -v yq &> /dev/null; then
    echo "yq not found. Installing yq..."
    pacman -Sy --noconfirm yq || { echo "Failed to install yq. Please install it manually."; exit 1; }
fi

# Determine target disk
TARGET_DISK=""

# Check if /mnt is already mounted (resuming or converging)
if mountpoint -q /mnt; then
    # Detect the underlying device for /mnt
    MOUNT_SOURCE=$(findmnt -n -o SOURCE /mnt)
    echo ">>> /mnt is already mounted from $MOUNT_SOURCE"

    echo ">>> Skipping disk selection as filesystem is mounted."

    if ! mountpoint -q /mnt/efi; then
        echo ">>> /mnt/efi is not mounted. Attempting to mount..."
        echo "Warning: /mnt/efi not mounted. Please ensure it is mounted for UKI generation."
    fi

else
    # Not mounted, so we choose a disk and converge storage
    if confirm_step "Disk Selection & Storage Setup" "This step will allow you to select a disk, partition it (EFI + LUKS), format it (BTRFS), and mount subvolumes. \nWARNING: This can be destructive if you choose to wipe."; then
        choose_target_disk
        wipe_disk "$TARGET_DISK"
        converge_storage "$TARGET_DISK"
    fi
fi

# Run convergence steps
if confirm_step "Package Installation" "This step will install base packages, kernels, firmware, and desktop environments (KDE/GNOME) defined in config/packages.yaml using pacstrap."; then
    converge_packages
fi

if confirm_step "GPU Driver Setup" "This step will install GPU drivers based on config/gpu.yaml."; then
    converge_gpu
fi

if confirm_step "mkinitcpio & UKI Generation" "This step will:\n1. Configure mkinitcpio hooks (systemd, etc.) from config/mkinitcpio.yaml.\n2. Generate Unified Kernel Images (UKIs) for kernels defined in config/boot.yaml.\n3. Sign UKIs with sbctl for Secure Boot.\n4. Enroll Secure Boot keys (requires Setup Mode)."; then
    converge_mkinitcpio
fi

if confirm_step "Bootloader Setup" "This step will install systemd-boot, configure loader.conf, and sign the bootloader binaries with sbctl."; then
    converge_boot
fi

echo "Installation / convergence completed successfully."
