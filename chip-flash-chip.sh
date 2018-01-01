#!/bin/bash

# Tools
FEL=sunxi-fel

# NAND
NAND_PAGE_SIZE=16384
NAND_OOB_SIZE=1664

# FDT file name
FDT_FILE=sun5i-r8-chip.dtb

# Function used to retrieve file size
filesize() {
  stat --printf="%s" $1
}

# Function used to wait until CHIP is connected and jumpered in FEL mode
wait_for_fel() {
  local TIMEOUT=30
  for ((i=$TIMEOUT; i>0; i--)) {
    if ${FEL} $@ ver 2>/dev/null >/dev/null; then
      return 0;
    fi
    echo -n ".";
    sleep 1
  }
  return 1
}

# Function used to wait until CHIP boots
wait_for_boot() {
  local TIMEOUT=120
  for ((i=$TIMEOUT; i>0; i--)) {
    if lsusb | grep -q "0525:a4a7"; then
      return 0;
    fi
    echo -n ".";
    sleep 3
  }
  return 1
}

# Images directory
IMAGES_DIR=$1
echo "Images directory: $IMAGES_DIR"

# Expected files
SPL="$IMAGES_DIR/sunxi-spl.bin"
SPL_PADDED="$IMAGES_DIR/sunxi-spl-with-ecc.bin"
UBOOT="$IMAGES_DIR/u-boot-dtb.bin"
UBI="$IMAGES_DIR/rootfs.ubi"

if [[ ! -e "${SPL}" ]]; then
  echo "ERROR: file ${SPL} not found"
  exit 1
fi
if [[ ! -e "${SPL_PADDED}" ]]; then
  echo "ERROR: file ${SPL_PADDED} not found"
  exit 1
fi
if [[ ! -e "${UBOOT}" ]]; then
  echo "ERROR: file ${UBOOT} not found"
  exit 1
fi
if [[ ! -e "${UBI}" ]]; then
  echo "ERROR: file ${UBI} not found"
  exit 1
fi

# SRAM addresses
SPL_PADDED_MEM_ADDR=0x43000000
UBOOT_SCRIPT_MEM_ADDR=0x43100000
UBOOT_MEM_ADDR=0x4a000000
UBI_MEM_ADDR=0x4b000000

# Create temporary working directory
TMPDIR=`mktemp -d -t chip-flash-XXXXXX`

# Compute SPL_PADDED_SIZE in pages
SPL_PADDED_SIZE=$(filesize "${SPL_PADDED}")
SPL_PADDED_SIZE=$(($SPL_PADDED_SIZE / ($NAND_PAGE_SIZE + $NAND_OOB_SIZE)))
SPL_PADDED_SIZE=$(echo $SPL_PADDED_SIZE | xargs printf "0x%08x")

# Compute UBI size in bytes
UBI_SIZE=`filesize $UBI | xargs printf "0x%08x"`

echo == Preparing u-boot ==
UBOOT_PADDED_SIZE=0x400000
UBOOT_PADDED="$TMPDIR/u-boot-padded-dtb.bin"
dd if="$UBOOT" of="$UBOOT_PADDED" bs=4M conv=sync
echo OK

echo == Preparing u-boot script ==
UBOOT_SCRIPT_SRC="$TMPDIR/u-boot-script.txt"
UBOOT_SCRIPT_BIN="$TMPDIR/u-boot-script.bin"
echo "nand erase.chip" > "${UBOOT_SCRIPT_SRC}"
echo "nand write.raw.noverify $SPL_PADDED_MEM_ADDR 0x0 $SPL_PADDED_SIZE" >> "${UBOOT_SCRIPT_SRC}"
echo "nand write.raw.noverify $SPL_PADDED_MEM_ADDR 0x400000 $SPL_PADDED_SIZE" >> "${UBOOT_SCRIPT_SRC}"
echo "nand write $UBOOT_MEM_ADDR 0x800000 $UBOOT_PADDED_SIZE" >> "${UBOOT_SCRIPT_SRC}"
echo "nand write.slc-mode.trimffs $UBI_MEM_ADDR 0x1000000 $UBI_SIZE" >> "${UBOOT_SCRIPT_SRC}"
echo "env default -a" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv bootargs root=ubi0:rootfs rootfstype=ubifs rw earlyprintk ubi.mtd=4" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv bootcmd 'if test -n \${fel_booted} && test -n \${scriptaddr}; then echo '(FEL boot)'; source \${scriptaddr}; fi; mtdparts; ubi part UBI; ubifsmount ubi0:rootfs; ubifsload \$fdt_addr_r /boot/\$fdtfile; ubifsload \$kernel_addr_r /boot/zImage; bootz \$kernel_addr_r - \$fdt_addr_r'" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv fdtfile $FDT_FILE" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv fel_booted 0" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv stdin serial" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv stdout serial" >> "${UBOOT_SCRIPT_SRC}"
echo "setenv stderr serial" >> "${UBOOT_SCRIPT_SRC}"
echo "saveenv" >> "${UBOOT_SCRIPT_SRC}"
echo "mw \${scriptaddr} 0x0" >> "${UBOOT_SCRIPT_SRC}"
echo "boot" >> "${UBOOT_SCRIPT_SRC}"
mkimage -A arm -T script -C none -n "u-boot script" -d "${UBOOT_SCRIPT_SRC}" "${UBOOT_SCRIPT_BIN}"
echo OK

echo == Waiting for CHIP connected and jumpered in FEL mode ==
if ! wait_for_fel; then
  echo "ERROR: please make sure CHIP is connected and jumpered in FEL mode"
  exit 1
fi
echo OK

echo == Upload spl to SRAM and execute it ==
${FEL} spl "${SPL}"
echo OK

# Wait for DRAM initialization to complete
sleep 1

echo == Upload spl to SRAM ==
${FEL} write $SPL_PADDED_MEM_ADDR "${SPL_PADDED}" || ( echo "ERROR: could not write ${SPL_PADDED}" && exit $? )
echo OK

echo == Upload u-boot to SRAM ==
${FEL} write $UBOOT_MEM_ADDR "${UBOOT_PADDED}" || ( echo "ERROR: could not write ${UBOOT_PADDED}" && exit $? )
echo OK

echo == Upload u-boot script to SRAM ==
${FEL} write $UBOOT_SCRIPT_MEM_ADDR "${UBOOT_SCRIPT_BIN}" || ( echo "ERROR: could not write ${UBOOT_SCRIPT_BIN}" && exit $? )
echo OK

echo == Upload ubi to SRAM ==
${FEL} --progress write $UBI_MEM_ADDR "${UBI}" || ( echo "ERROR: could not write ${UBI}" && exit $? )
echo OK

echo == Execute the main u-boot binary ==
${FEL} exe $UBOOT_MEM_ADDR || ( echo "ERROR: could not execute u-boot binary" && exit $? )
echo OK

echo == Waiting for CHIP to flash and boot ==
if ! wait_for_boot; then
  echo "ERROR: could not flash or boot"
  exit 1
fi
echo OK

echo == Flashing completed successfully ==
rm -rf $TMPDIR
