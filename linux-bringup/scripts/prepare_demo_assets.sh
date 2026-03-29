#!/usr/bin/env bash
set -euo pipefail

ROOT=/root/chipyard/fpga/linux-bringup/demo-assets
DTB_DIR=$ROOT/dtb

mkdir -p "$ROOT" "$DTB_DIR"

python3 - <<'PY'
from pathlib import Path

root = Path("/root/chipyard/fpga/linux-bringup/demo-assets")
(root / "kernel-demo.bin").write_bytes((b"KERNEL-DEMO-" * 64)[:1024])
(root / "payload-demo.bin").write_bytes((b"PAYLOAD-DEMO-" * 64)[:1024])
PY

cat > "$DTB_DIR/demo-frontchain.dts" <<'EOF'
/dts-v1/;
/ {
  compatible = "chipyard,zcu104-linux-frontchain-demo";
  model = "demo-frontchain";
  chosen {
    bootargs = "console=ttyS0,115200 earlycon";
  };
};
EOF

dtc -I dts -O dtb -o "$DTB_DIR/demo-frontchain.dtb" "$DTB_DIR/demo-frontchain.dts"

echo "[info] Generated demo assets:"
echo "  /root/chipyard/fpga/linux-bringup/demo-assets/kernel-demo.bin"
echo "  /root/chipyard/fpga/linux-bringup/demo-assets/payload-demo.bin"
echo "  /root/chipyard/fpga/linux-bringup/demo-assets/dtb/demo-frontchain.dtb"
echo "  (Use build_demo_jump_target.sh for the real jump target ELF/BIN)"
