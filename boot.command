#!/bin/bash

echo "Advanced macOS Boot Repair Script v3"
echo "WARNING: This script modifies critical system configurations. Ensure you have a backup before proceeding."

read -p "Continue? (y/n) " choice
if [ "$choice" != "y" ]; then
  echo "Exiting..."
  exit 1
fi

DISK="disk0"

# Identify the main macOS volume
VOLUME_IDENTIFICATION_METHODS=(
  "grep 'Apple_APFS' | awk '{print $NF}'"
  "grep 'Apple_HFS' | awk '{print $NF}'"
  "diskutil apfs list | grep 'Volume Name' | head -1 | awk '{print $NF}'"
)

for method in "${VOLUME_IDENTIFICATION_METHODS[@]}"; do
  MAIN_VOLUME=$(diskutil list $DISK | eval $method)
  if [[ ! -z "$MAIN_VOLUME" ]]; then
    break
  fi
done

if [[ -z "$MAIN_VOLUME" ]]; then
  echo "Unable to identify the main macOS volume. Exiting."
  exit 1
fi

# Repair permissions
echo "Repairing permissions for main macOS volume..."
diskutil resetUserPermissions / `id -u`

# Repair main volume
echo "Verifying and repairing main macOS volume..."
diskutil verifyVolume $MAIN_VOLUME
diskutil repairVolume $MAIN_VOLUME

# Set startup disk
echo "Checking startup disk settings..."
startup_disk=$(bless --getBoot)
if [[ "$startup_disk" != *"$MAIN_VOLUME"* ]]; then
  echo "Setting $MAIN_VOLUME as the startup disk..."
  bless --setBoot $MAIN_VOLUME
fi

# Kernel Extension Cache Rebuild
echo "Rebuilding kernel extension cache..."
kmutil install --update-all --volume-root $MAIN_VOLUME

# Re-bless Boot Volume
BLESSED_FOLDERS=(
  "$MAIN_VOLUME"/System/Library/CoreServices
  "$MAIN_VOLUME"/System/Library/CoreServices/boot.efi
)
for folder in "${BLESSED_FOLDERS[@]}"; do
  if [[ -d "$folder" || -f "$folder" ]]; then
    echo "Re-blessing using $folder..."
    bless --folder "$folder" --bootefi --create-snapshot
  fi
done

# Boot Support Partitions Repair
echo "Checking boot support partitions..."
diskutil list | grep 'Apple_Boot' | awk '{print $8}' | while read volume; do
  echo "Verifying and repairing $volume..."
  diskutil verifyVolume "$volume"
  diskutil repairVolume "$volume"
done

# PRAM Battery Check (Older Macs)
if system_profiler SPPowerDataType | grep "Condition" | grep -q "Replace"; then
  echo "The battery may need to be replaced. This can cause boot issues on older Macs."
fi

# rEFInd installation
read -p "Would you like to install rEFInd boot manager? (y/n) " choice
if [ "$choice" == "y" ]; then
  echo "Downloading rEFInd..."
  curl -L -O "https://downloads.sourceforge.net/project/refind/0.14.0.2/refind-bin-0.14.0.2.zip?ts=gAAAAABk8QqQmbbYW5bGH98CGOR2R6mdcK4X4Eu0UZVE9uWDb-542sCma2KtazzHCVM6RkYalRXPud7Zs7Jct927q6TAEABsWA%3D%3D&use_mirror=zenlayer&r=" -o refind.zip

  echo "Unzipping rEFInd..."
  unzip refind.zip -d refind

  echo "Installing rEFInd..."
  ./refind/refind-install

  echo "rEFInd should now be installed."
fi

# Final Recommendations and restart prompt
echo "If issues persist, consider manually resetting the SMC and NVRAM."
read -p "Would you like to restart now? (y/n) " restart_choice
if [ "$restart_choice" == "y" ]; then
  echo "Restarting..."
  shutdown -r now
else
  echo "Finished repairs. Please restart your computer when ready."
fi
