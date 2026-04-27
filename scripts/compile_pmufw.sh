#!/bin/bash
# Compile ZynqMP PMUFW using Windows mb-gcc.exe via WSL
# Run from Linux (WSL) - requires mb-gcc.exe accessible at VIVADO_DIR

set -e

VIVADO_DIR=/mnt/e/PRO_APP/xilinx/Vivado/2021.2
EMBEDDEDSW=$VIVADO_DIR/data/embeddedsw
MB_BIN=$VIVADO_DIR/gnu/microblaze/nt/bin
PMUFW_ORIG=$EMBEDDEDSW/lib/sw_apps/zynqmp_pmufw
WORK=/tmp/pmufw_staging
OUT=/tmp/pmufw_build/pmufw.elf

echo "[1/5] Setting up PATH with mb-gcc wrappers..."
mkdir -p /tmp/pmufw_wrappers
for tool in mb-gcc mb-ar mb-ranlib mb-objcopy mb-ld mb-as mb-nm mb-size mb-gcc-ar mb-gcc-ranlib mb-gcc-nm; do
    cat > /tmp/pmufw_wrappers/$tool << WRAPPER
#!/bin/bash
exec "$MB_BIN/${tool}.exe" "\$@"
WRAPPER
    chmod +x /tmp/pmufw_wrappers/$tool
done
export PATH=/tmp/pmufw_wrappers:$PATH

# Quick sanity check
mb-gcc --version | head -1

echo "[2/5] Creating staging tree..."
rm -rf $WORK
mkdir -p $WORK

# Create embeddedsw-compatible directory tree using symlinks
# copy_bsp.sh uses relative paths from misc/: ../../../.. => embeddedsw
mkdir -p $WORK/lib/sw_apps/zynqmp_pmufw
mkdir -p $WORK/XilinxProcessorIPLib

# Point to original Vivado locations via symlinks
ln -s $EMBEDDEDSW/lib/bsp/standalone_v7_6/src $WORK/lib/bsp_standalone_src 2>/dev/null || \
    ln -s $(ls -d $EMBEDDEDSW/lib/bsp/standalone_v* | sort -V | tail -1)/src $WORK/lib/bsp_standalone_src

# Copy pmufw src and misc to staging
cp -r $PMUFW_ORIG/src $WORK/lib/sw_apps/zynqmp_pmufw/
cp -r $PMUFW_ORIG/misc $WORK/lib/sw_apps/zynqmp_pmufw/

echo "[3/5] Running copy_bsp.sh from staging area..."
# We need to create an embeddedsw-like layout so copy_bsp.sh paths resolve
# EMBEDDED_SW_DIR = WORKING_DIR/../../../../ from src/ = staging/lib/sw_apps/zynqmp_pmufw/misc/../../../../ = staging/
STAGING_EMBEDDEDSW=$WORK

# Create required directory structure in staging
mkdir -p $STAGING_EMBEDDEDSW/XilinxProcessorIPLib/drivers
mkdir -p $STAGING_EMBEDDEDSW/lib/bsp/standalone
mkdir -p $STAGING_EMBEDDEDSW/lib/sw_services

# Symlink drivers (versioned -> unversioned)
DRIVERS_BASE=$EMBEDDEDSW/XilinxProcessorIPLib/drivers
for drv in avbuf canps csudma uartps ipipsu ttcps emacps iicps sdps qspipsu gpiops usbpsu wdtps sysmonpsu zdma dpdma dppsu video_common cpu; do
    versioned=$(ls -d $DRIVERS_BASE/${drv}_v* 2>/dev/null | sort -V | tail -1)
    if [ -n "$versioned" ]; then
        ln -s "$versioned" $STAGING_EMBEDDEDSW/XilinxProcessorIPLib/drivers/$drv 2>/dev/null || true
    fi
done

# Symlink standalone bsp (pick latest version)
STANDALONE_VER=$(ls -d $EMBEDDEDSW/lib/bsp/standalone_v* 2>/dev/null | sort -V | tail -1)
ln -s "$STANDALONE_VER" $STAGING_EMBEDDEDSW/lib/bsp/standalone 2>/dev/null || true

# Symlink sw_services (xilfpga, xilsecure, xilskey)
for svc in xilfpga xilsecure xilskey; do
    ln -s $EMBEDDEDSW/lib/sw_services/$svc $STAGING_EMBEDDEDSW/lib/sw_services/$svc 2>/dev/null || true
done

# Now run copy_bsp.sh from the staging src directory
cd $WORK/lib/sw_apps/zynqmp_pmufw/src
bash ../misc/copy_bsp.sh 2>&1 || true

BSP_DIR=$WORK/lib/sw_apps/zynqmp_pmufw/misc/zynqmp_pmufw_bsp/psu_pmu_0
if [ ! -d "$BSP_DIR/include" ]; then
    echo "ERROR: BSP directory not created properly"
    exit 1
fi
echo "BSP structure OK: $(ls $BSP_DIR/)"

echo "[4/5] Compiling BSP (libxil.a)..."
BSP_MAKEFILE=$WORK/lib/sw_apps/zynqmp_pmufw/misc/zynqmp_pmufw_bsp/Makefile

if [ ! -f "$BSP_MAKEFILE" ]; then
    echo "ERROR: BSP Makefile not found at $BSP_MAKEFILE"
    exit 1
fi

cd $WORK/lib/sw_apps/zynqmp_pmufw/misc/zynqmp_pmufw_bsp
make -j4 CC=mb-gcc AR=mb-ar RANLIB=mb-ranlib 2>&1 | tail -10

echo "[5/5] Compiling pmufw application..."
mkdir -p /tmp/pmufw_build
cd $WORK/lib/sw_apps/zynqmp_pmufw/src
make -j4 CC=mb-gcc AR=mb-ar RANLIB=mb-ranlib 2>&1 | tail -20

if [ -f "executable.elf" ]; then
    cp executable.elf $OUT
    echo "SUCCESS: pmufw.elf written to $OUT"
    ls -lh $OUT
else
    echo "ERROR: executable.elf not found"
    ls *.elf 2>/dev/null || echo "no .elf files"
    exit 1
fi
