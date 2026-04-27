#!/bin/bash
# compile_pmufw_v2.sh - Build ZynqMP pmufw.elf using Windows mb-gcc.exe via WSL
# Uses explicit versioned paths, bypasses copy_bsp.sh symlink issues.

set -e
trap 'echo "ERROR at line $LINENO"' ERR

VIVADO=/mnt/e/PRO_APP/xilinx/Vivado/2021.2
EMBEDDEDSW=$VIVADO/data/embeddedsw
EMBEDDEDSW_FSBL=/tmp/embeddedsw   # Fallback: has PS drivers (iicps, canps, gpiops, etc.)
MB_BIN=$VIVADO/gnu/microblaze/nt/bin
PMUFW_ORIG=$EMBEDDEDSW/lib/sw_apps/zynqmp_pmufw
BSP_BASE=/tmp/pmufw_bsp
SRC_DIR=/tmp/pmufw_src
OUT=/tmp/pmufw_build/pmufw.elf

# --- Versioned library paths ---
XILFPGA=$EMBEDDEDSW/lib/sw_services/xilfpga_v6_1/src
XILSECURE=$EMBEDDEDSW/lib/sw_services/xilsecure_v4_6/src
XILSKEY=$EMBEDDEDSW/lib/sw_services/xilskey_v7_2/src
STANDALONE=$EMBEDDEDSW/lib/bsp/standalone_v7_6/src
DRIVERS=$EMBEDDEDSW/XilinxProcessorIPLib/drivers

echo "=== [1/6] Setup mb-gcc wrappers ==="
mkdir -p /tmp/mb_wrappers
for tool in mb-gcc mb-ar mb-ranlib mb-objcopy mb-ld mb-as mb-nm mb-size mb-gcc-ar mb-gcc-ranlib mb-gcc-nm; do
    printf '#!/bin/bash\nexec "%s/%s.exe" "$@"\n' "$MB_BIN" "$tool" > /tmp/mb_wrappers/$tool
    chmod +x /tmp/mb_wrappers/$tool
done
export PATH=/tmp/mb_wrappers:$PATH
mb-gcc --version | head -1

echo "=== [2/6] Setup BSP directories ==="
BSP_PMU=$BSP_BASE/psu_pmu_0
rm -rf $BSP_BASE $SRC_DIR
mkdir -p $BSP_PMU/{include,lib,code}
mkdir -p $BSP_PMU/libsrc/standalone/src
mkdir -p $BSP_PMU/libsrc/xilfpga/src
mkdir -p $BSP_PMU/libsrc/xilsecure/src
mkdir -p $BSP_PMU/libsrc/xilskey/src

echo "=== [3/6] Copy BSP files (explicit versioned paths) ==="

# --- standalone BSP ---
cp -r $STANDALONE/common/*        $BSP_PMU/libsrc/standalone/src/ 2>/dev/null || true
cp    $STANDALONE/microblaze/*    $BSP_PMU/libsrc/standalone/src/ 2>/dev/null || true
cp -r $STANDALONE/profile         $BSP_PMU/libsrc/standalone/src/ 2>/dev/null || true
cp    $STANDALONE/common/*.h      $BSP_PMU/include/ 2>/dev/null || true
cp    $STANDALONE/microblaze/*.h  $BSP_PMU/include/ 2>/dev/null || true
cp    $STANDALONE/profile/*.h     $BSP_PMU/include/ 2>/dev/null || true
# misc files
cp $PMUFW_ORIG/misc/bspconfig.h   $BSP_PMU/include/
cp $PMUFW_ORIG/misc/xfpga_config.h $BSP_PMU/include/
cp $PMUFW_ORIG/misc/inbyte.c $PMUFW_ORIG/misc/outbyte.c  $BSP_PMU/libsrc/standalone/src/
cp $PMUFW_ORIG/misc/config.make   $BSP_PMU/libsrc/standalone/src/

# --- xilfpga ---
cp -r $XILFPGA/*                  $BSP_PMU/libsrc/xilfpga/src/ 2>/dev/null || true
cp    $XILFPGA/interface/zynqmp/xilfpga_pcap.c $BSP_PMU/libsrc/xilfpga/src/ 2>/dev/null || true
cp    $XILFPGA/*.h                $BSP_PMU/include/ 2>/dev/null || true
cp    $XILFPGA/interface/zynqmp/*.h $BSP_PMU/include/ 2>/dev/null || true
rm -rf $BSP_PMU/libsrc/xilfpga/src/interface 2>/dev/null || true

# --- xilsecure ---
cp $XILSECURE/Makefile            $BSP_PMU/libsrc/xilsecure/src/
cp -r $XILSECURE/common/*         $BSP_PMU/libsrc/xilsecure/src/ 2>/dev/null || true
cp -r $XILSECURE/zynqmp/*         $BSP_PMU/libsrc/xilsecure/src/ 2>/dev/null || true
cp    $XILSECURE/common/*.h       $BSP_PMU/include/ 2>/dev/null || true
cp    $XILSECURE/zynqmp/*.h       $BSP_PMU/include/ 2>/dev/null || true

# --- xilskey ---
# XILSKEY points to the src/ dir itself; must place into libsrc/xilskey/src/
mkdir -p $BSP_PMU/libsrc/xilskey/src
cp -r $XILSKEY/. $BSP_PMU/libsrc/xilskey/src/
# Remove files not needed for PMU
for f in xilskey_epl.c xilskey_eps.c xilskey_jscmd.c xilskey_jslib.c xilskey_bbram.c xilskey_bbramps_zynqmp.c; do
    rm -f $BSP_PMU/libsrc/xilskey/src/$f 2>/dev/null || true
done
cp $BSP_PMU/libsrc/xilskey/src/*.h        $BSP_PMU/include/ 2>/dev/null || true
cp $BSP_PMU/libsrc/xilskey/src/include/*.h $BSP_PMU/include/ 2>/dev/null || true

# --- Drivers ---
find_driver_latest() {
    local name=$1
    # First try Vivado embeddedsw
    local versioned=$(ls -d $EMBEDDEDSW/XilinxProcessorIPLib/drivers/${name}_v* 2>/dev/null | sort -V | tail -1)
    if [ -n "$versioned" ]; then
        echo "$versioned"
        return
    fi
    # Fallback: FSBL embeddedsw (has PS drivers like iicps, canps, gpiops, etc.)
    local fsbl_drv=$EMBEDDEDSW_FSBL/XilinxProcessorIPLib/drivers/$name
    if [ -d "$fsbl_drv" ]; then
        echo "$fsbl_drv"
        return
    fi
    echo ""
}

for drv in avbuf canps csudma uartps ipipsu ttcps emacps iicps sdps qspipsu gpiops usbpsu wdtps sysmonpsu zdma dpdma dppsu video_common; do
    versioned=$(find_driver_latest $drv)
    if [ -n "$versioned" ] && [ -d "$versioned/src" ]; then
        mkdir -p $BSP_PMU/libsrc/$drv/src
        cp -r $versioned/src/* $BSP_PMU/libsrc/$drv/src/ 2>/dev/null || true
        cp $versioned/src/*.h  $BSP_PMU/include/ 2>/dev/null || true
        # Copy HSM-generated _g.c file from pmufw misc
        [ "$drv" != "avbuf" ] && [ "$drv" != "video_common" ] && \
            cp $PMUFW_ORIG/misc/x${drv}_g.c $BSP_PMU/libsrc/$drv/src/ 2>/dev/null || true
    else
        echo "  WARNING: driver '$drv' not found, skipping"
    fi
done

# CPU driver
CPU_VER=$(find_driver_latest cpu)
if [ -n "$CPU_VER" ] && [ -d "$CPU_VER/src" ]; then
    mkdir -p $BSP_PMU/libsrc/cpu/src
    cp -r $CPU_VER/src/* $BSP_PMU/libsrc/cpu/src/ 2>/dev/null || true
fi

# xparameters.h
cp $PMUFW_ORIG/misc/xparameters.h $BSP_PMU/include/

echo "BSP setup done. include: $(ls $BSP_PMU/include/*.h | wc -l) headers"

echo "=== [4/6] Create BSP top-level Makefile ==="
# Copy the Makefile from misc (it's the BSP-level Makefile)
cp $PMUFW_ORIG/misc/Makefile $BSP_BASE/
# Patch out forced parallel par_libs to avoid ar.exe race on Windows NTFS
sed -i 's/$(MAKE) -j --no-print-directory par_libs/$(MAKE) --no-print-directory par_libs/' $BSP_BASE/Makefile

echo "=== [5/6] Compile BSP ==="
cd $BSP_BASE
# Use -j1 (serial) to avoid ar race condition on parallel lib updates
make -j1 CC=mb-gcc AR=mb-ar RANLIB=mb-ranlib 2>&1 | tail -20
echo "BSP make exit: $?"

# Check that libxil.a was built
LIBXIL=$BSP_PMU/lib/libxil.a
if [ ! -f "$LIBXIL" ]; then
    echo "ERROR: libxil.a not found at $LIBXIL"
    ls $BSP_PMU/lib/ 2>/dev/null || echo "(lib dir empty)"
    exit 1
fi
echo "libxil.a built: $(ls -lh $LIBXIL)"

echo "=== [6/6] Compile pmufw application ==="
cp -r $PMUFW_ORIG/src $SRC_DIR
cd $SRC_DIR

# Patch Makefile to point to our BSP location
sed -i "s|LIBS := ../misc/zynqmp_pmufw_bsp/psu_pmu_0/lib/libxil.a|LIBS := $BSP_PMU/lib/libxil.a|" Makefile
sed -i "s|INCLUDEPATH := -I../misc/zynqmp_pmufw_bsp/psu_pmu_0/include -I\.|INCLUDEPATH := -I$BSP_PMU/include -I.|" Makefile
sed -i "s|LIBPATH := -L../misc/zynqmp_pmufw_bsp/psu_pmu_0/lib|LIBPATH := -L$BSP_PMU/lib|" Makefile
# Skip the $(LIBS) make target (BSP already compiled) by making it a no-op
sed -i 's|$(LIBS):|\$(LIBS):\n\t@echo "BSP already compiled"\n\nxxx_disable_original_libs_target:|' Makefile 2>/dev/null || true

# Build
make -j4 CC=mb-gcc AR=mb-ar RANLIB=mb-ranlib EXEC=pmufw.elf 2>&1 | tail -30
echo "pmufw make exit: $?"

if [ -f "pmufw.elf" ]; then
    mkdir -p /tmp/pmufw_build
    cp pmufw.elf $OUT
    echo "SUCCESS: $OUT"
    ls -lh $OUT
    mb-size pmufw.elf 2>/dev/null || true
elif [ -f "executable.elf" ]; then
    mkdir -p /tmp/pmufw_build
    cp executable.elf $OUT
    echo "SUCCESS (as executable.elf): $OUT"
    ls -lh $OUT
else
    echo "ERROR: no elf output found"
    ls *.elf 2>/dev/null || echo "no .elf"
    exit 1
fi
