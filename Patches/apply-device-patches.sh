#!/bin/bash
echo "- Applying local device specific patches for $DEVICE_IMPORT..."

# Patcher helper
apply_local_patches() {
    local patch_dir=$1
    local ignore_failure=$2
    echo "-- Applying patches from: $patch_dir"
    for patch_file in "$patch_dir"/*.patch; do
        if [ -f "$patch_file" ]; then
            echo "--- Applying: $(basename "$patch_file")"
            if patch -s -p1 --fuzz=5 < "$patch_file"; then
                echo "--- Success: $(basename "$patch_file")"
            else
                if [ "$ignore_failure" == "true" ]; then
                    echo "--- Warning: Failed to apply $(basename "$patch_file"), assuming already applied."
                else
                    echo "Fatal: Failed to apply $patch_file"
                    exit 1
                fi
            fi
        fi
    done
}

# Single patch helper
apply_single_patch() {
    local patch_file=$1
    if [ -f "$patch_file" ]; then
        echo "-- Applying single patch: $(basename "$patch_file")"
        patch -s -p1 --fuzz=5 < "$patch_file" || { echo "Fatal: Failed to apply $patch_file"; exit 1; }
    else
        echo "Fatal: Patch $patch_file not found"
        exit 1
    fi
}

PATCH_ROOT="/tmp/Patches/device/sweet"

case "$DEVICE_IMPORT" in
    sweet)
        echo "-- Applying LN8K patches..."
        apply_local_patches "$PATCH_ROOT/ln8k" "false"
        echo "CONFIG_CHARGER_LN8000=y" >> "$MAIN_DEFCONFIG"

        echo "-- Applying DTBO patches (skipping if already applied)..."
        apply_local_patches "$PATCH_ROOT/dtbo" "true"

        echo "-- Applying LTO fix..."
        apply_single_patch "$PATCH_ROOT/fix_lto.patch"
        echo "CONFIG_LTO_CLANG=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_THINLTO=y" >> "$MAIN_DEFCONFIG"

        echo "-- Applying KPATCH fix..."
        apply_single_patch "$PATCH_ROOT/kpatch_fix.patch"

        echo "-- Tuning default configs..."
        echo "CONFIG_EROFS_FS=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_SECURITY_SELINUX_DEVELOP=y" >> "$MAIN_DEFCONFIG"

        # Local Baseband Guard logic
        if [ "$BASEBAND_GUARD_ENABLE" == "true" ]; then
            echo "-- Applying Local Baseband Guard..."
            cp /tmp/Patches/bbg.c security/
            cp /tmp/Patches/bbg.h security/
            
            # Use the local setup script logic but adapt for our paths
            # The setup.sh from vc-teahouse adds it to security/Makefile etc.
            # For now, let's just run the setup script if it's there
            chmod +x /tmp/Patches/setup-bbg.sh
            bash /tmp/Patches/setup-bbg.sh
        fi
        ;;
    *)
        echo "No local patches configured for $DEVICE_IMPORT."
        ;;
esac
