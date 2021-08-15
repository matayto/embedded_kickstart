#!/usr/bin/env bash
# tested on Fedora 34

ISO_NAME="Rocky-8.4-x86_64-minimal"
ISO_URL="https://download.rockylinux.org/pub/rocky/8/isos/x86_64/${ISO_NAME}.iso"
ISO_SHA256="0de5f12eba93e00fefc06cdb0aa4389a0972a4212977362ea18bde46a1a1aa4f"
ISO_DIR="/isobuild"
ISO_DIR_TMP="${ISO_DIR}/tmp"
ISO_DIR_RO="${ISO_DIR_TMP}/ro"
ISO_DIR_RW="${ISO_DIR_TMP}/rw"
ISO_DIR_MNT="${ISO_DIR_TMP}/mnt"
ISO_SRC="${ISO_DIR_TMP}/${ISO_NAME}.iso"
ISO_DST="${ISO_DIR_TMP}/${ISO_NAME}-ks.iso"
KS_FILE="/isobuild/kickstart_el8.cfg"

if ! rpm -q xorriso > /dev/null 2>&1; then
 dnf install -y xorriso
fi

for dir in "${ISO_DIR}" "${ISO_DIR_TMP}" "${ISO_DIR_RO}" "${ISO_DIR_RW}" "${ISO_DIR_MNT}"; do
  [ -d "${dir}" ] || mkdir -v "${dir}"
done

[ -f ${ISO_SRC} ] || wget -O "${ISO_SRC}" "${ISO_URL}"

download_sha256=$(sha256sum "${ISO_SRC}" | cut -d' ' -f1)
if [[ "${ISO_SHA256}" != "${download_sha256}" ]]; then
  echo "Downloaded ISO sha256sum does not match expected value."
  exit 1
fi

mount -t iso9660 -o loop "${ISO_SRC}" "${ISO_DIR_RO}"

for modfile in 'isolinux/isolinux.cfg' 'EFI/BOOT/grub.cfg' 'images/efiboot.img'; do
  [ -d "$(dirname ${ISO_DIR_RW}/${modfile})" ] || mkdir -p "$(dirname ${ISO_DIR_RW}/${modfile})"
  /bin/cp -a "${ISO_DIR_RO}/${modfile}" "${ISO_DIR_RW}/${modfile}"
  sync
  if [[ "${modfile}" =~ .cfg$ ]]; then
    if ! grep -q "ks\.cfg" "${ISO_DIR_RW}/${modfile}"; then
      echo "Adding ks.cfg to ${modfile}"
      sed -r -i "s,(.*)(hd:LABEL=\S+)(.*),\1\2 inst.ks=\2:/ks.cfg\3,g" "${ISO_DIR_RW}/${modfile}"
    fi
  fi
done

umount "${ISO_DIR_RO}"

# Adjust legacy boot menu isolinux.cfg
sed -i "/menu default/d" "${ISO_DIR_RW}/isolinux/isolinux.cfg"

# adjust EFI/BOOT/grub.cfg and inject into images/efiboot.img
sed -i 's,set default=.*,set default="0",' "${ISO_DIR_RW}/EFI/BOOT/grub.cfg"
#grep 'set default' "${ISO_DIR_RW}/EFI/BOOT/grub.cfg"
mount "${ISO_DIR_RW}/images/efiboot.img" "${ISO_DIR_MNT}"
cp -avf "${ISO_DIR_RW}/EFI/BOOT/grub.cfg" "${ISO_DIR_MNT}/EFI/BOOT/grub.cfg"
umount "${ISO_DIR_MNT}"

# mv or rm outdev file before recreating
xorriso \
  -indev "${ISO_SRC}" \
  -map "${KS_FILE}" /ks.cfg \
  -map "${ISO_DIR_RW}" / \
  -boot_image any replay \
  -outdev "${ISO_DST}"

# where '/dev/sdX' is bootable external storage device
# dd if=${ISO_DST} of=/dev/sdX bs=8192 conv=fdatasync
