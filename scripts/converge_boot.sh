#!/usr/bin/env bash
set -Eeuo pipefail

# Function to converge bootloader configuration
# Installs systemd-boot and signs it for Secure Boot.
converge_boot() {
  echo ">>> Installing systemd-boot..."

  # Install bootloader
  # --esp-path=/efi is where we mounted the EFI partition
  arch-chroot /mnt bootctl install --esp-path=/efi

  echo ">>> Configuring systemd-boot..."
  # Configure loader.conf
  # We set a timeout and default entry (though UKIs are auto-detected)
  cat <<EOF > /mnt/efi/loader/loader.conf
timeout 20
console-mode max
editor no
EOF

  echo ">>> Signing bootloader with sbctl..."
  # Sign the installed bootloader binary
  # The path is usually /efi/EFI/BOOT/BOOTX64.EFI and /efi/EFI/systemd/systemd-bootx64.efi
  # sbctl sign -s handles the database update

  local bootloader_efi="/efi/EFI/BOOT/BOOTX64.EFI"
  local systemd_efi="/efi/EFI/systemd/systemd-bootx64.efi"

  if [ -f "/mnt$bootloader_efi" ]; then
      echo "    Signing $bootloader_efi..."
      arch-chroot /mnt sbctl sign -s "$bootloader_efi"
  fi

  if [ -f "/mnt$systemd_efi" ]; then
      echo "    Signing $systemd_efi..."
      arch-chroot /mnt sbctl sign -s "$systemd_efi"
  fi

  # Note: We do not install kernels here anymore, as they are installed in converge_packages
  # and UKIs are generated in converge_mkinitcpio.
}
