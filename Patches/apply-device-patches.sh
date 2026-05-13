#!/bin/bash
echo "- Applying local device specific patches for $DEVICE_IMPORT..."

# Patcher helper
apply_local_patches() {
    local patch_dir=$1
    echo "-- Applying patches from: $patch_dir"
    for patch_file in "$patch_dir"/*.patch; do
        if [ -f "$patch_file" ]; then
            echo "--- Applying: $(basename "$patch_file")"
            # Using -N to ignore already applied patches and -r - to avoid reject files
            if patch -s -f -p1 --fuzz=5 < "$patch_file"; then
                echo "--- Success: $(basename "$patch_file")"
            else
                echo "--- Warning: Failed to apply $(basename "$patch_file"), assuming already applied or incompatible."
            fi
        fi
    done
}

# Single patch helper
apply_single_patch() {
    local patch_file=$1
    if [ -f "$patch_file" ]; then
        echo "-- Applying single patch: $(basename "$patch_file")"
        if patch -s -f -p1 --fuzz=5 < "$patch_file"; then
            echo "--- Success: $(basename "$patch_file")"
        else
            echo "--- Warning: Failed to apply $(basename "$patch_file"), assuming already applied or incompatible."
        fi
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
        # Disable generic charger to ensure LN8K is used
        sed -i '/CONFIG_BQ25890_CHARGER/d' "$MAIN_DEFCONFIG"
        echo "CONFIG_CHARGER_LN8000=y" >> "$MAIN_DEFCONFIG"
        # Disable MODVERSIONS as it conflicts with LTO on 4.14
        sed -i 's/CONFIG_MODVERSIONS=y/CONFIG_MODVERSIONS=n/g' "$MAIN_DEFCONFIG"
        echo "CONFIG_MODVERSIONS=n" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_UNUSED_SYMBOLS=n" >> "$MAIN_DEFCONFIG"

        # echo "-- Applying DTBO patches..."
        # apply_local_patches "$PATCH_ROOT/dtbo"

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
            
            chmod +x /tmp/Patches/setup-bbg.sh
            bash /tmp/Patches/setup-bbg.sh
        fi

        echo "-- Ensuring KernelSU (KowSU) 4.14 Compatibility..."
        # Force hooks
        grep -q "kernelsu" drivers/Makefile || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
        grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig || sed -i '$i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
        
        # Path to actual source (build-ready clones it to KernelSU folder in workspace root)
        KSU_SRC="../KernelSU/kernel"
        
        if [ -d "$KSU_SRC" ]; then
            echo "--- Patching KSU source at $KSU_SRC"
            # Fix syscall_fn_t error
            if [ -f "$KSU_SRC/hook/syscall_hook.h" ]; then
                sed -i '1i typedef void (*syscall_fn_t)(void);' "$KSU_SRC/hook/syscall_hook.h"
            fi

            # Fix MODULE_IMPORT_NS error (not supported in 4.14)
            # We delete the line entirely as it's the safest way to avoid implicit-int errors
            find "$KSU_SRC" -name "*.c" -exec sed -i '/MODULE_IMPORT_NS/d' {} +
        else
            echo "--- Warning: KSU source not found at $KSU_SRC, trying local drivers/kernelsu"
            find drivers/kernelsu -name "*.c" -exec sed -i '/MODULE_IMPORT_NS/d' {} +
        fi

        # Ensure it's enabled in defconfig (removing any 'is not set' lines first)
        sed -i '/CONFIG_KSU/d' "$MAIN_DEFCONFIG"
        sed -i '/CONFIG_KPROBES/d' "$MAIN_DEFCONFIG"
        sed -i '/CONFIG_KALLSYMS/d' "$MAIN_DEFCONFIG"
        
        echo "CONFIG_KSU=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_KSU_SUSFS=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_KPROBES=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_KALLSYMS=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_KALLSYMS_ALL=y" >> "$MAIN_DEFCONFIG"
        echo "CONFIG_EXT4_FS=y" >> "$MAIN_DEFCONFIG"
        ;;
    *)
        echo "No local patches configured for $DEVICE_IMPORT."
        ;;
esac
