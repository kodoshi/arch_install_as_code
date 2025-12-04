#!/usr/bin/env bash
set -Eeuo pipefail

# Function to converge GPU drivers
# Installs the appropriate GPU drivers based on configuration.
converge_gpu() {
  local cfg="config/gpu.yaml"
  echo ">>> Converging GPU drivers..."

  local driver
  driver=$(yq -r '.gpu.driver' "$cfg")

  echo "    Selected driver: $driver"

  case "$driver" in
    nouveau)
        pacstrap /mnt mesa xf86-video-nouveau
        ;;
    nvidia-dkms)
        pacstrap /mnt nvidia-dkms nvidia-utils
        ;;
    nvidia-open)
        pacstrap /mnt nvidia-open nvidia-utils
        ;;
    *)
        echo "Error: Unknown GPU driver '$driver' in $cfg"
        exit 1
        ;;
  esac
}
