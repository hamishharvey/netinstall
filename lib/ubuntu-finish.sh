#!/bin/bash

if [ ! -f /var/log/netinstall.log ] ; then
	touch /var/log/netinstall.log
	echo "NetInstall Log:" >> /var/log/netinstall.log
fi

#Device Configuration:
if [ ! -f /boot/uboot/SOC.sh ] ; then
	cp /etc/hwpack/SOC.sh /boot/uboot/SOC.sh
	echo "ERROR: [boot/uboot/SOC.sh] was missing..." >> /var/log/netinstall.log
fi
. /boot/uboot/SOC.sh

if [ ! -d /boot/uboot/backup/ ] ; then
	mkdir -p /boot/uboot/backup/
fi
ls -lh /boot/uboot/* >/boot/uboot/backup/file_list.log

echo "fdisk -l..." >> /var/log/netinstall.log
fdisk -l >> /var/log/netinstall.log

#Set boot flag on: /dev/mmcblk0:
if [ -f /sbin/parted ] ; then
	/sbin/parted /dev/mmcblk0 set 1 boot on || true
else
	echo "ERROR: [/sbin/parted /dev/mmcblk0 set 1 boot on] failed" >> /var/log/netinstall.log
fi

#Find Target Partition and FileSystem
if [ -f /boot/uboot/mounts ] ; then
	echo "cat /boot/uboot/mounts..." >> /var/log/netinstall.log
	cat /boot/uboot/mounts >> /var/log/netinstall.log
	FINAL_PART=$(cat /boot/uboot/mounts | grep /dev/ | grep "/target " | awk '{print $1}')
	FINAL_FSTYPE=$(cat /boot/uboot/mounts | grep /dev/ | grep "/target " | awk '{print $3}')
else
	echo "ERROR: [/boot/uboot/mounts] was missing..." >> /var/log/netinstall.log
fi

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage.net || true
rm -f /boot/uboot/zImage.net || true
rm -f /boot/uboot/initrd.net || true

#Cleanup: Ubuntu's mess of backup files
rm -f /boot/uboot/uInitrd || true
rm -f /boot/uboot/uInitrd.bak || true
rm -f /boot/uboot/uImage || true
rm -f /boot/uboot/uImage.bak || true

#Fake flash-kernel (precise)
rm -rf /boot/vmlinuz || true
rm -rf /boot/initrd.img || true

#Fake flash-kernel (quantal)
rm -rf /boot/vmlinuz- || true
rm -rf /boot/uboot/vmlinuz- || true
rm -rf /boot/initrd.img- || true

#Cleanup: Initial Bootloader
rm -f /boot/uboot/boot.scr || true
rm -f /boot/uboot/boot.scr.bak || true
rm -f /boot/uboot/uEnv.txt || true
rm -f /boot/uboot/uEnv.txt.bak || true
rm -f /boot/uboot/preEnv.txt || true

#Restore backup MLO (SPL) Bootloader?
rm -f /boot/uboot/MLO || true
rm -f /boot/uboot/MLO.bak || true

if [ -f /boot/uboot/backup/MLO ] ; then
	mv /boot/uboot/backup/MLO /boot/uboot/MLO
fi

#Restore, backup u-boot Bootloader?
rm -f /boot/uboot/u-boot.bin || true
rm -f /boot/uboot/u-boot.bin.bak || true
rm -f /boot/uboot/u-boot.img || true
rm -f /boot/uboot/u-boot.img.bak || true

if [ -f /boot/uboot/backup/u-boot.img ] ; then
	mv /boot/uboot/backup/u-boot.img /boot/uboot/u-boot.img
fi

if [ -f /boot/uboot/backup/u-boot.bin ] ; then
	mv /boot/uboot/backup/u-boot.bin /boot/uboot/u-boot.bin
fi

if [ "${dd_uboot_seek}" ] && [ "${dd_uboot_bs}" ] ; then
	if [ -f /boot/uboot/backup/u-boot.imx ] ; then
		dd if=/boot/uboot/backup/u-boot.imx of=/dev/mmcblk0 seek=${dd_uboot_seek} bs=${dd_uboot_bs}
	fi
fi

if [ -f "/boot/uboot/backup/boot.scr" ] ; then
	mv /boot/uboot/backup/boot.scr /boot/uboot/boot.scr
else
	echo "WARN: [/boot/uboot/backup/boot.scr] was missing..." >> /var/log/netinstall.log
fi

if [ -f "/boot/uboot/backup/normal.txt" ] ; then
	sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
	sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
	mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
else
	echo "WARN: [/boot/uboot/backup/normal.txt] was missing..." >> /var/log/netinstall.log
fi

#Cleanup: some of Ubuntu's packages:
apt-get remove -y linux-image-omap* || true
apt-get remove -y linux-headers-omap* || true
apt-get remove -y u-boot-linaro* || true
apt-get remove -y x-loader-omap* || true
apt-get remove -y flash-kernel || true
apt-get -y autoremove || true

if [ "x${serial_tty}" != "x" ] ; then
	cat > /etc/init/${serial_tty}.conf <<-__EOF__
		start on stopped rc RUNLEVEL=[2345]
		stop on runlevel [!2345]

		respawn
		exec /sbin/getty 115200 ${serial_tty}

	__EOF__
else
	echo "WARN: [serial_tty] was undefined..." >> /var/log/netinstall.log
fi

if [ "x${boot_fstype}" = "xext2" ] ; then
	echo "/dev/mmcblk0p1    /boot/uboot    ext2    defaults    0    2" >> /etc/fstab
else
	echo "/dev/mmcblk0p1    /boot/uboot    auto    defaults    0    0" >> /etc/fstab
fi

if [ "x${usbnet_mem}" != "x" ] ; then
	echo "vm.min_free_kbytes = ${usbnet_mem}" >> /etc/sysctl.conf
fi

cat > /etc/init/board_tweaks.conf <<-__EOF__
	start on runlevel 2

	script
	if [ -f /boot/uboot/SOC.sh ] ; then
	        board=\$(cat /boot/uboot/SOC.sh | grep "board" | awk -F"=" '{print \$2}')
	        case "\${board}" in
	        BEAGLEBONE_A)
	                if [ -f /boot/uboot/tools/target/BeagleBone.sh ] ; then
	                        /bin/sh /boot/uboot/tools/target/BeagleBone.sh &> /dev/null &
	                fi;;
	        esac
	fi
	end script

__EOF__

#Install Correct Kernel Image: (this will fail if the boot partition was re-formated)
if [ -f /boot/uboot/linux-image-*_1.0*_arm*.deb ] ; then
	dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
	update-initramfs -c -k `uname -r`
	cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
	cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img
	rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

	#FIXME: Also reinstall these:
	rm -f /boot/uboot/*dtbs.tar.gz || true
	rm -f /boot/uboot/*modules.tar.gz || true

	mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
	if [ "${zreladdr}" ] ; then
		mkimage -A arm -O linux -T kernel -C none -a ${zreladdr} -e ${zreladdr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
	fi
else
	echo "ERROR: [/boot/uboot/linux-image-*.deb] missing" >> /var/log/netinstall.log
fi
