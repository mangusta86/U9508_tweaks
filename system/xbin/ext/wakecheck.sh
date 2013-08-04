#!/system/xbin/sh

BB=/system/xbin/busybox

#$BB mount -o remount,rw /
$BB echo "0" > /tmp/early_wakeup;

(
	$BB cat /sys/power/wait_for_fb_wake > /dev/null 2>&1;
	$BB echo "1" > /tmp/early_wakeup;
)&
