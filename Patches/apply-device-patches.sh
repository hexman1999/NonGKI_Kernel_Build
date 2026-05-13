#!/bin/bash
echo "- Applying local device specific patches for $DEVICE_IMPORT..."

# Patcher helper
apply_local_patches() {
    local patch_dir=$1
    echo "-- Applying patches from: $patch_dir"
    for patch_file in "$patch_dir"/*.patch; do
        if [ -f "$patch_file" ]; then
            echo "--- Applying: $(basename "$patch_file")"
            patch -s -p1 --fuzz=5 < "$patch_file" || { echo "Fatal: Failed to apply $patch_file"; exit 1; }
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
        apply_local_patches "$PATCH_ROOT/ln8k"
        echo "CONFIG_CHARGER_LN8000=y" >> "$MAIN_DEFCONFIG"

        echo "-- Applying DTBO & LTO patches..."
        apply_local_patches "$PATCH_ROOT/dtbo"
        apply_single_patch "$PATCH_ROOT/fix_lto.patch"
        echo "CONFIG_LTO_CLANG=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_THINLTO=y" >> "$MAIN_DEFCONFIG"

        echo "-- Applying KPATCH fix..."
        apply_single_patch "$PATCH_ROOT/kpatch_fix.patch"

        echo "-- Tuning default configs..."
        echo "CONFIG_EROFS_FS=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_SECURITY_SELINUX_DEVELOP=y" >> "$MAIN_DEFCONFIG"
        ;;
    *)
        echo "No local patches configured for $DEVICE_IMPORT."
        ;;
esac
