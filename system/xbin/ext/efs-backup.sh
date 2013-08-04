#!/system/xbin/sh

BB=/system/bin/busybox

if [ ! -f /data/.siyah/modembackup.tar.gz ]; then
	$BB mkdir /data/.siyah;
	$BB chmod 777 /data/.siyah;
	$BB tar zcvf /data/.siyah/modembackup.tar.gz /modem;
	$BB dd if=/dev/block/mmcblk0p3 of=/data/.siyah/modemdev-mmcblk0p3.img bs=512;
	$BB gzip /data/.siyah/modemdev-mmcblk0p3.img;
	$BB cp /data/.siyah/modem* /data/share/;
	$BB chmod 777 /data/share/modemdev-mmcblk0p3.img;
	$BB chmod 777 /data/share/modembackup.tar.gz;
	(
		sleep 120;
		cp /data/share/modem* /storage/sdcard1/;
	)&
fi;
