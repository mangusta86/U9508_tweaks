#!/system/bin/sh

# Created By Dorimanx and Dairinin / Adapted by Mangusta


# allow custom user jobs
if [ ! -e /data/crontab/root ]; then
	mkdir /data/crontab/;
	cp -a /res/crontab_service/root /data/crontab/;
	chown 0:0 /data/crontab/root;
	chmod 777 /data/crontab/root;
fi;

{
	if [ ! -e /system/etc/cron.d/crontabs/root ]; then
		mkdir -p /system/etc/cron.d/crontabs/;
		cp -a /data/crontab/root /system/etc/cron.d/crontabs/;
		chown 0:0 /system/etc/cron.d/crontabs/*;
		chmod 777 /system/etc/cron.d/crontabs/*;
	fi;
	echo "root:x:0:0::/system/etc/cron.d/crontabs:/system/bin/sh" > /etc/passwd;
}

# set timezone
TZ=UTC

# set cron timezone
export TZ

#Set Permissions to scripts
chown 0:0 /data/crontab/cron-scripts/*;
chmod 777 /data/crontab/cron-scripts/*;

# use /system/etc/cron.d/crontabs/ call the crontab file "root" for JB ROMS
if [ -e /system/xbin/busybox ]; then
		nohup /system/xbin/busybox crond -c /system/etc/cron.d/crontabs/
elif [ -e /system/bin/busybox ]; then
		nohup /system/bin/busybox crond -c /system/etc/cron.d/crontabs/
fi;
