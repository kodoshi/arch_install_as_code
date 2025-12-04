#!/usr/bin/env bash
set -Eeuo pipefail

# Function to converge packages
# This script installs the base system and selected desktop environments.
# It is designed to be idempotent-ish (pacstrap can be run multiple times).
converge_packages() {
    local cfg="config/packages.yaml"

    echo ">>> Reading package lists from $cfg..."
    # Base packages
    mapfile -t base_pkgs < <(yq -r '.packages.base[]' "$cfg")

    # Desktop environments: KDE Plasma 6 + GNOME
    mapfile -t kde_pkgs   < <(yq -r '.packages.desktop.kde[]' "$cfg")
    mapfile -t gnome_pkgs < <(yq -r '.packages.desktop.gnome[]' "$cfg")

    # Display manager (SDDM)
    mapfile -t dm_pkgs < <(yq -r '.packages.display_manager[]' "$cfg")

    echo ">>> Installing base system, KDE Plasma, GNOME, and SDDM into /mnt..."
    # pacstrap installs packages into the new root.
    # It is generally safe to run multiple times; it will reinstall/update packages.
    pacstrap -K /mnt \
        "${base_pkgs[@]}" \
        "${kde_pkgs[@]}" \
        "${gnome_pkgs[@]}" \
        "${dm_pkgs[@]}"

    echo ">>> Generating fstab..."
    # Only generate fstab if it doesn't exist or is empty to avoid duplication
    if [ ! -s /mnt/etc/fstab ]; then
        genfstab -U /mnt >> /mnt/etc/fstab
        echo "    fstab generated."
    else
        echo "    fstab already exists, skipping generation."
    fi

    echo ">>> Enabling NetworkManager and SDDM inside chroot..."
    # Enable services if not already enabled
    arch-chroot /mnt systemctl enable NetworkManager.service
    arch-chroot /mnt systemctl enable sddm.service
}
