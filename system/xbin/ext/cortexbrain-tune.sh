#!/system/bin/sh

#Credits:
# Zacharias.maladroit
# Voku1987
# Collin_ph@xda
# Dorimanx@xda
# Gokhanmoral@xda
# Johnbeetee
# Alucard_24@xda
# Modded by Mangusta for U9508

# TAKE NOTE THAT LINES PRECEDED BY A "#" IS COMMENTED OUT.
#
# This script must be activated after init start =< 25sec or parameters from /sys/* will not be loaded.


# ==============================================================
# GLOBAL VARIABLES || without "local" also a variable in a function is global
# ==============================================================

FILE_NAME=$0;
PIDOFCORTEX=$$;
# (since we don't have the recovery source code I can't change the ".siyah" dir, so just leave it there for history)
DATA_DIR=/data/.siyah;
WAS_IN_SLEEP_MODE=1;
NOW_CALL_STATE=0;
USB_POWER=0;
# read sd-card size, set via boot
SDCARD_SIZE=`cat /tmp/sdcard_size`;

# ==============================================================
# INITIATE
# ==============================================================

# get values from profile
PROFILE=`cat $DATA_DIR/.active.profile`;
. $DATA_DIR/${PROFILE}.profile;

# check if dumpsys exist in ROM
if [ -e /system/bin/dumpsys ]; then
	DUMPSYS_STATE=1;
else
	DUMPSYS_STATE=0;
fi;

# set initial vm.dirty vales
echo "500" > /proc/sys/vm/dirty_writeback_centisecs;
echo "1000" > /proc/sys/vm/dirty_expire_centisecs;

# ==============================================================
# FILES FOR VARIABLES || we need this for write variables from child-processes to parent
# ==============================================================

# WIFI HELPER
WIFI_HELPER_AWAKE="$DATA_DIR/WIFI_HELPER_AWAKE";
WIFI_HELPER_TMP="$DATA_DIR/WIFI_HELPER_TMP";
echo "1" > $WIFI_HELPER_TMP;

# MOBILE HELPER
MOBILE_HELPER_AWAKE="$DATA_DIR/MOBILE_HELPER_AWAKE";
MOBILE_HELPER_TMP="$DATA_DIR/MOBILE_HELPER_TMP";
echo "1" > $MOBILE_HELPER_TMP;

# ==============================================================
# I/O-TWEAKS 
# ==============================================================
IO_TWEAKS()
{
	if [ "$cortexbrain_io" == on ]; then

		local i="";

		local MMC=`ls -d /sys/block/mmc*`;
		for i in $MMC; do
			if [ -e $i/queue/scheduler ]; then
				echo $scheduler > $i/queue/scheduler;
			fi;

			if [ -e $i/queue/rotational ]; then
				echo "0" > $i/queue/rotational;
			fi;

			if [ -e $i/queue/iostats ]; then
				echo "0" > $i/queue/iostats;
			fi;

			if [ -e $i/queue/nr_requests ]; then
				echo "128" > $i/queue/nr_requests; # default: 128
			fi;
		done;

		# our storage is 16GB, best is 1024KB readahead
		# see https://github.com/Keff/samsung-kernel-msm7x30/commit/a53f8445ff8d947bd11a214ab42340cc6d998600#L1R627
		echo "1024" > /sys/block/mmcblk0/queue/read_ahead_kb;

		if [ -e /sys/block/mmcblk1/queue/read_ahead_kb ]; then
			if [ "$cortexbrain_read_ahead_kb" -eq "0" ]; then

				if [ "$SDCARD_SIZE" -eq "1" ]; then
					echo "256" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "4" ]; then
					echo "512" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "8" ] || [ "$SDCARD_SIZE" -eq "16" ]; then
					echo "1024" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "32" ]; then
					echo "2048" > /sys/block/mmcblk1/queue/read_ahead_kb;
				elif [ "$SDCARD_SIZE" -eq "64" ]; then
					echo "2560" > /sys/block/mmcblk1/queue/read_ahead_kb;
				fi;

			else
				echo "$cortexbrain_read_ahead_kb" > /sys/block/mmcblk1/queue/read_ahead_kb;
			fi;
		fi;

		echo "45" > /proc/sys/fs/lease-break-time;

		log -p i -t $FILE_NAME "*** IO_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
IO_TWEAKS;

# ==============================================================
# KERNEL-TWEAKS
# ==============================================================
KERNEL_TWEAKS()
{
	local state="$1";

	if [ "$cortexbrain_kernel_tweaks" == on ]; then

		if [ "$state" == "awake" ]; then
			echo "0" > /proc/sys/vm/oom_kill_allocating_task;
			echo "0" > /proc/sys/vm/panic_on_oom;
			echo "120" > /proc/sys/kernel/panic;
		elif [ "$state" == "sleep" ]; then
			echo "0" > /proc/sys/vm/oom_kill_allocating_task;
			echo "0" > /proc/sys/vm/panic_on_oom;
			echo "90" > /proc/sys/kernel/panic;
		else
			echo "0" > /proc/sys/vm/oom_kill_allocating_task;
			echo "0" > /proc/sys/vm/panic_on_oom;
			echo "120" > /proc/sys/kernel/panic;
		fi;

		if [ "$cortexbrain_memory" == on ]; then
			echo "32 32" > /proc/sys/vm/lowmem_reserve_ratio;
		fi;

		log -p i -t $FILE_NAME "*** KERNEL_TWEAKS ***: $state ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
KERNEL_TWEAKS;

# ==============================================================
# SYSTEM-TWEAKS
# ==============================================================
SYSTEM_TWEAKS()
{
	if [ "$cortexbrain_system" == on ]; then
		setprop hwui.render_dirty_regions false;
		setprop windowsmgr.max_events_per_sec 90;
		setprop profiler.force_disable_err_rpt 1;
		setprop profiler.force_disable_ulog 1;

		log -p i -t $FILE_NAME "*** SYSTEM_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
SYSTEM_TWEAKS;

# ==============================================================
# BATTERY-TWEAKS
# ==============================================================


BATTERY_TWEAKS()
{
	if [ "$cortexbrain_battery" == on ]; then

		# battery-calibration if battery is full
		local LEVEL=`cat /sys/class/power_supply/Battery/capacity`;
		local CURR_ADC=`cat /sys/class/power_supply/Battery/current_now`;
		local BATTFULL=`cat /sys/class/power_supply/Battery/capacity_level`;
		local i="";
		local bus="";

		log -p i -t $FILE_NAME "*** BATTERY - LEVEL: $LEVEL - CUR: $CURR_ADC ***";

		if [ "$LEVEL" -eq "100" ] && [ "$BATTFULL" == "Full" ]; then
			rm -f /data/system/batterystats.bin;
			log -p i -t $FILE_NAME "battery-calibration done ...";
		fi;

#		# LCD: power-reduce
#		if [ -e /sys/class/lcd/panel/power_reduce ]; then
#			if [ "$power_reduce" == on ]; then
#				echo "1" > /sys/class/lcd/panel/power_reduce;
#			else
#				echo "0" > /sys/class/lcd/panel/power_reduce;
#			fi;
#		fi;

		# USB: power support
		local POWER_LEVEL=`ls /sys/bus/usb/devices/*/power/control`;
		for i in $POWER_LEVEL; do
			chmod 777 $i;
			echo "auto" > $i;
		done;

		local POWER_AUTOSUSPEND=`ls /sys/bus/usb/devices/*/power/autosuspend`;
		for i in $POWER_AUTOSUSPEND; do
			chmod 777 $i;
			echo "1" > $i;
		done;

		# BUS: power support
		local buslist="i2c sdio";
		for bus in $buslist; do
			local POWER_CONTROL=`ls /sys/bus/$bus/devices/*/power/control`;
			for i in $POWER_CONTROL; do
				chmod 777 $i;
				echo "auto" > $i;
			done;
		done;

		log -p i -t $FILE_NAME "*** BATTERY_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
# run this tweak once, if the background-process is disabled
if [ "$cortexbrain_background_process" -eq "0" ]; then
	BATTERY_TWEAKS;
fi;

# ==============================================================
# CPU-TWEAKS
# ==============================================================
# TODO check compatibility

CPU_INTELLI_PLUG_TWEAKS()
{
	local SYSTEM_GOVERNOR=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`;
	local intelli_plug_active_tmp="/sys/module/intelli_plug/parameters/intelli_plug_active";

	if [ -e $intelli_plug_active_tmp ]; then
		local IPA_CHECK=`cat $intelli_plug_active_tmp`;

		local hotplug_enable_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/hotplug_enable";
		local gov_check="0";

		if [ ! -e $hotplug_enable_tmp ]; then
			hotplug_enable_tmp="/dev/null";
		fi;

		if [ "$SYSTEM_GOVERNOR" != "nightmare" ] && [ "$SYSTEM_GOVERNOR" != "darkness" ]; then
			gov_check=1;
		fi;

		if [ "a$IPA_CHECK" == "a1" ]; then
			if [ "$hotplug_enable" -eq "1" ]; then
				if [ "$SYSTEM_GOVERNOR" == "nightmare" ] || [ "$SYSTEM_GOVERNOR" == "darkness" ]; then
					echo "0" > $intelli_plug_active_tmp;

					log -p i -t $FILE_NAME "*** CPU_INTELLI_PLUG ***: disabled";
				fi;
			fi;
		else
			if [ "$hotplug_enable" -eq "0" ] || [ "$gov_check" -eq "1" ]; then
				echo "1" > $intelli_plug_active_tmp;

				log -p i -t $FILE_NAME "*** CPU_INTELLI_PLUG ***: enabled";
			fi;
		fi;
		echo "$hotplug_enable" > $hotplug_enable_tmp;
	fi;
}

CPU_GOV_TWEAKS()
{
	local state="$1";

	if [ "$cortexbrain_cpu" == on ]; then
		local SYSTEM_GOVERNOR=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`;

		local sampling_rate_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_rate";
		if [ ! -e $sampling_rate_tmp ]; then
			sampling_rate_tmp="/dev/null";
		fi;

		local cpu_up_rate_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/cpu_up_rate";
		if [ ! -e $cpu_up_rate_tmp ]; then
			cpu_up_rate_tmp="/dev/null";
		fi;

		local cpu_down_rate_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/cpu_down_rate";
		if [ ! -e $cpu_down_rate_tmp ]; then
			cpu_down_rate_tmp="/dev/null";
		fi;

		local up_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold";
		if [ ! -e $up_threshold_tmp ]; then
			up_threshold_tmp="/dev/null";
		fi;

		local up_threshold_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_at_min_freq";
		if [ ! -e $up_threshold_at_min_freq_tmp ]; then
			up_threshold_at_min_freq_tmp="/dev/null";
		fi;

		local up_threshold_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_min_freq";
		if [ ! -e $up_threshold_min_freq_tmp ]; then
			up_threshold_min_freq_tmp="/dev/null";
		fi;

		local inc_cpu_load_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/inc_cpu_load_at_min_freq";
		if [ ! -e $inc_cpu_load_at_min_freq_tmp ]; then
			inc_cpu_load_at_min_freq_tmp="/dev/null";
		fi;

		local hotplug_freq_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/hotplug_freq_1_1";
		if [ ! -e $hotplug_freq_fst_tmp ]; then
			hotplug_freq_fst_tmp="/dev/null";
		fi;

		local hotplug_freq_snd_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/hotplug_freq_2_0";
		if [ ! -e $hotplug_freq_snd_tmp ]; then
			hotplug_freq_snd_tmp="/dev/null";
		fi;

		local up_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_load";
		if [ ! -e $up_load_tmp ]; then
			up_load_tmp="/dev/null";
		fi;

		local down_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_load";
		if [ ! -e $down_load_tmp ]; then
			down_load_tmp="/dev/null";
		fi;

		local down_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_threshold";
		if [ ! -e $down_threshold_tmp ]; then
			down_threshold_tmp="/dev/null";
		fi;

		local sampling_up_factor_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_up_factor";
		if [ ! -e $sampling_up_factor_tmp ]; then
			sampling_up_factor_tmp="/dev/null";
		fi;

		local sampling_down_factor_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_factor";
		if [ ! -e $sampling_down_factor_tmp ]; then
			sampling_down_factor_tmp="/dev/null";
		fi;

		local down_differential_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_differential";
		if [ ! -e $down_differential_tmp ]; then
			down_differential_tmp="/dev/null";
		fi;

		local freq_for_responsiveness_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_for_responsiveness";
		if [ ! -e $freq_for_responsiveness_tmp ]; then
			freq_for_responsiveness_tmp="/dev/null";
		fi;

		local freq_responsiveness_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_responsiveness";
		if [ ! -e $freq_responsiveness_tmp ]; then
			freq_responsiveness_tmp="/dev/null";
		fi;

		local freq_for_responsiveness_max_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_for_responsiveness_max";
		if [ ! -e $freq_for_responsiveness_max_tmp ]; then
			freq_for_responsiveness_max_tmp="/dev/null";
		fi;

		local freq_step_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_at_min_freq";
		if [ ! -e $freq_step_at_min_freq_tmp ]; then
			freq_step_at_min_freq_tmp="/dev/null";
		fi;

		local freq_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step";
		if [ ! -e $freq_step_tmp ]; then
			freq_step_tmp="/dev/null";
		fi;

		local freq_step_dec_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_dec";
		if [ ! -e $freq_step_dec_tmp ]; then
			freq_step_dec_tmp="/dev/null";
		fi;

		local freq_step_dec_at_max_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_step_dec_at_max_freq";
		if [ ! -e $freq_step_dec_at_max_freq_tmp ]; then
			freq_step_dec_at_max_freq_tmp="/dev/null";
		fi;

		local up_sf_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_sf_step";
		if [ ! -e $up_sf_step_tmp ]; then
			up_sf_step_tmp="/dev/null";
		fi;

		local down_sf_step_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_sf_step";
		if [ ! -e $down_sf_step_tmp ]; then
			down_sf_step_tmp="/dev/null";
		fi;

		local inc_cpu_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/inc_cpu_load";
		if [ ! -e $inc_cpu_load_tmp ]; then
			inc_cpu_load_tmp="/dev/null";
		fi;

		local dec_cpu_load_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/dec_cpu_load";
		if [ ! -e $dec_cpu_load_tmp ]; then
			dec_cpu_load_tmp="/dev/null";
		fi;

		local freq_up_brake_at_min_freq_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_up_brake_at_min_freq";
		if [ ! -e $freq_up_brake_at_min_freq_tmp ]; then
			freq_up_brake_at_min_freq_tmp="/dev/null";
		fi;

		local freq_up_brake_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_up_brake";
		if [ ! -e $freq_up_brake_tmp ]; then
			freq_up_brake_tmp="/dev/null";
		fi;

		local cpu_load_bias_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/cpu_load_bias";
		if [ ! -e $cpu_load_bias_tmp ]; then
			cpu_load_bias_tmp="/dev/null";
		fi;

		# merge up_threshold_at_min_freq & up_threshold_min_freq => up_threshold_at_min_freq_tmp
		if [ $up_threshold_at_min_freq_tmp == "/dev/null" ] && [ $up_threshold_min_freq_tmp != "/dev/null" ]; then
			up_threshold_at_min_freq_tmp=$up_threshold_min_freq_tmp;
		fi;

		# merge freq_for_responsiveness_tmp & freq_responsiveness_tmp => freq_for_responsiveness_tmp
		if [ $freq_for_responsiveness_tmp == "/dev/null" ] && [ $freq_responsiveness_tmp != "/dev/null" ]; then
			freq_for_responsiveness_tmp=$freq_responsiveness_tmp;
		fi;

		local sampling_down_max_mom_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_max_mom";
		if [ ! -e $sampling_down_max_mom_tmp ]; then
			sampling_down_max_mom_tmp="/dev/null";
		fi;

		local sampling_down_mom_sens_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/sampling_down_mom_sens";
		if [ ! -e $sampling_down_mom_sens_tmp ]; then
			sampling_down_mom_sens_tmp="/dev/null";
		fi;

		local up_threshold_hp_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/up_threshold_hotplug1";
		if [ ! -e $up_threshold_hp_fst_tmp ]; then
			up_threshold_hp_fst_tmp="/dev/null";
		fi;

		local down_threshold_hp_fst_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/down_threshold_hotplug1";
		if [ ! -e $down_threshold_hp_fst_tmp ]; then
			down_threshold_hp_fst_tmp="/dev/null";
		fi;

		local smooth_up_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/smooth_up";
		if [ ! -e $smooth_up_tmp ]; then
			smooth_up_tmp="/dev/null";
		fi;

		local freq_limit_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/freq_limit";
		if [ ! -e $freq_limit_tmp ]; then
			freq_limit_tmp="/dev/null";
		fi;

		local fast_scaling_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/fast_scaling";
		if [ ! -e $fast_scaling_tmp ]; then
			fast_scaling_tmp="/dev/null";
		fi;

		local early_demand_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/early_demand";
		if [ ! -e $early_demand_tmp ]; then
			early_demand_tmp="/dev/null";
		fi;

		local grad_up_threshold_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/grad_up_threshold";
		if [ ! -e $grad_up_threshold_tmp ]; then
			grad_up_threshold_tmp="/dev/null";
		fi;

		local disable_hotplug_tmp="/sys/devices/system/cpu/cpufreq/$SYSTEM_GOVERNOR/disable_hotplug";
		if [ ! -e $disable_hotplug_tmp ]; then
			disable_hotplug_tmp="/dev/null";
		fi;

		# sleep-settings
		if [ "$state" == "sleep" ]; then
			echo "$sampling_rate_sleep" > $sampling_rate_tmp;
			echo "$cpu_up_rate_sleep" > $cpu_up_rate_tmp;
			echo "$cpu_down_rate_sleep" > $cpu_down_rate_tmp;
			echo "$up_threshold_sleep" > $up_threshold_tmp;
			echo "$up_threshold_at_min_freq_sleep" > $up_threshold_at_min_freq_tmp;
			echo "$inc_cpu_load_at_min_freq_sleep" > $inc_cpu_load_at_min_freq_tmp;
			echo "$hotplug_freq_fst_sleep" > $hotplug_freq_fst_tmp;
			echo "$hotplug_freq_snd_sleep" > $hotplug_freq_snd_tmp;
			echo "$up_load_sleep" > $up_load_tmp;
			echo "$down_load_sleep" > $down_load_tmp;
			echo "$down_threshold_sleep" > $down_threshold_tmp;
			echo "$sampling_up_factor_sleep" > $sampling_up_factor_tmp;
			echo "$sampling_down_factor_sleep" > $sampling_down_factor_tmp;
			echo "$down_differential_sleep" > $down_differential_tmp;
			echo "$freq_step_at_min_freq_sleep" > $freq_step_at_min_freq_tmp;
			echo "$freq_step_sleep" > $freq_step_tmp;
			echo "$freq_step_dec_sleep" > $freq_step_dec_tmp;
			echo "$freq_step_dec_at_max_freq_sleep" > $freq_step_dec_at_max_freq_tmp;
			echo "$freq_for_responsiveness_sleep" > $freq_for_responsiveness_tmp;
			echo "$freq_for_responsiveness_max_sleep" > $freq_for_responsiveness_max_tmp;
			echo "$up_sf_step_sleep" > $up_sf_step_tmp;
			echo "$down_sf_step_sleep" > $down_sf_step_tmp;
			echo "$inc_cpu_load_sleep" > $inc_cpu_load_tmp;
			echo "$dec_cpu_load_sleep" > $dec_cpu_load_tmp;
			echo "$freq_up_brake_at_min_freq_sleep" > $freq_up_brake_at_min_freq_tmp;
			echo "$freq_up_brake_sleep" > $freq_up_brake_tmp;
			echo "$cpu_load_bias_sleep" > $cpu_load_bias_tmp;
			echo "$sampling_down_max_mom_sleep" > $sampling_down_max_mom_tmp;
			echo "$sampling_down_mom_sens_sleep" > $sampling_down_mom_sens_tmp;
			echo "$up_threshold_hp_fst_sleep" > $up_threshold_hp_fst_tmp;
			echo "$down_threshold_hp_fst_sleep" > $down_threshold_hp_fst_tmp;
			echo "$smooth_up_sleep" > $smooth_up_tmp;
			echo "$freq_limit_sleep" > $freq_limit_tmp;
			echo "$fast_scaling_sleep" > $fast_scaling_tmp;
			echo "$early_demand_sleep" > $early_demand_tmp;
			echo "$grad_up_threshold_sleep" > $grad_up_threshold_tmp;
			echo "$disable_hotplug_sleep" > $disable_hotplug_tmp;
		# awake-settings
		elif [ "$state" == "awake" ]; then
			echo "$sampling_rate" > $sampling_rate_tmp;
			echo "$cpu_up_rate" > $cpu_up_rate_tmp;
			echo "$cpu_down_rate" > $cpu_down_rate_tmp;
			echo "$up_threshold" > $up_threshold_tmp;
			echo "$up_threshold_at_min_freq" > $up_threshold_at_min_freq_tmp;
			echo "$inc_cpu_load_at_min_freq" > $inc_cpu_load_at_min_freq_tmp;
			echo "$hotplug_freq_fst" > $hotplug_freq_fst_tmp;
			echo "$hotplug_freq_snd" > $hotplug_freq_snd_tmp;
			echo "$up_load" > $up_load_tmp;
			echo "$down_load" > $down_load_tmp;
			echo "$down_threshold" > $down_threshold_tmp;
			echo "$sampling_up_factor" > $sampling_up_factor_tmp;
			echo "$sampling_down_factor" > $sampling_down_factor_tmp;
			echo "$down_differential" > $down_differential_tmp;
			echo "$freq_step_at_min_freq" > $freq_step_at_min_freq_tmp;
			echo "$freq_step" > $freq_step_tmp;
			echo "$freq_step_dec" > $freq_step_dec_tmp;
			echo "$freq_step_dec_at_max_freq" > $freq_step_dec_at_max_freq_tmp;
			echo "$freq_for_responsiveness" > $freq_for_responsiveness_tmp;
			echo "$freq_for_responsiveness_max" > $freq_for_responsiveness_max_tmp;
			echo "$up_sf_step" > $up_sf_step_tmp;
			echo "$down_sf_step" > $down_sf_step_tmp;
			echo "$inc_cpu_load" > $inc_cpu_load_tmp;
			echo "$dec_cpu_load" > $dec_cpu_load_tmp;
			echo "$freq_up_brake_at_min_freq" > $freq_up_brake_at_min_freq_tmp;
			echo "$freq_up_brake" > $freq_up_brake_tmp;
			echo "$cpu_load_bias" > $cpu_load_bias_tmp;
			echo "$sampling_down_max_mom" > $sampling_down_max_mom_tmp;
			echo "$sampling_down_mom_sens" > $sampling_down_mom_sens_tmp;
			echo "$up_threshold_hp_fst" > $up_threshold_hp_fst_tmp;
			echo "$down_threshold_hp_fst" > $down_threshold_hp_fst_tmp;
			echo "$smooth_up" > $smooth_up_tmp;
			echo "$freq_limit" > $freq_limit_tmp;
			echo "$fast_scaling" > $fast_scaling_tmp;
			echo "$early_demand" > $early_demand_tmp;
			echo "$grad_up_threshold" > $grad_up_threshold_tmp;
			echo "$disable_hotplug" > $disable_hotplug_tmp;
		fi;

		CPU_INTELLI_PLUG_TWEAKS;

		log -p i -t $FILE_NAME "*** CPU_GOV_TWEAKS: $state ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
# this needed for cpu tweaks apply from STweaks in real time
apply_cpu="$2";
if [ "$apply_cpu" == "update" ] || [ "$cortexbrain_background_process" -eq "0" ]; then
	CPU_GOV_TWEAKS "awake";
fi;

# ==============================================================
# MEMORY-TWEAKS
# ==============================================================
MEMORY_TWEAKS()
{
	if [ "$cortexbrain_memory" == on ]; then
		echo "$dirty_background_ratio" > /proc/sys/vm/dirty_background_ratio; # default: 10
		echo "$dirty_ratio" > /proc/sys/vm/dirty_ratio; # default: 20
		echo "4" > /proc/sys/vm/min_free_order_shift; # default: 4
		echo "1" > /proc/sys/vm/overcommit_memory; # default: 1
		echo "950" > /proc/sys/vm/overcommit_ratio; # default: 50
		echo "3" > /proc/sys/vm/page-cluster; # default: 3
		echo "8192" > /proc/sys/vm/min_free_kbytes;
		echo "16384" > /proc/sys/vm/mmap_min_addr;

		log -p i -t $FILE_NAME "*** MEMORY_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
MEMORY_TWEAKS;

# ==============================================================
# ENTROPY-TWEAKS
# ==============================================================

ENTROPY()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		if [ "$PROFILE" != "battery" ] || [ "$PROFILE" != "extreme_battery" ]; then
			echo "256" > /proc/sys/kernel/random/read_wakeup_threshold;
			echo "512" > /proc/sys/kernel/random/write_wakeup_threshold;
		else
			echo "128" > /proc/sys/kernel/random/read_wakeup_threshold;
			echo "128" > /proc/sys/kernel/random/write_wakeup_threshold;
		fi;
	elif [ "$state" == "sleep" ]; then
		echo "128" > /proc/sys/kernel/random/read_wakeup_threshold;
		echo "128" > /proc/sys/kernel/random/write_wakeup_threshold;
	fi;

	log -p i -t $FILE_NAME "*** ENTROPY ***: $state - $PROFILE";
}

# ==============================================================
# TCP-TWEAKS
# ==============================================================
TCP_TWEAKS()
{
	if [ "$cortexbrain_tcp" == on ]; then
		echo "0" > /proc/sys/net/ipv4/tcp_timestamps;
		echo "1" > /proc/sys/net/ipv4/tcp_tw_reuse;
		echo "1" > /proc/sys/net/ipv4/tcp_sack;
		echo "1" > /proc/sys/net/ipv4/tcp_tw_recycle;
		echo "1" > /proc/sys/net/ipv4/tcp_window_scaling;
		echo "1" > /proc/sys/net/ipv4/tcp_moderate_rcvbuf;
		echo "1" > /proc/sys/net/ipv4/route/flush;
		echo "2" > /proc/sys/net/ipv4/tcp_syn_retries;
		echo "2" > /proc/sys/net/ipv4/tcp_synack_retries;
		echo "10" > /proc/sys/net/ipv4/tcp_fin_timeout;
		echo "0" > /proc/sys/net/ipv4/tcp_ecn;
		echo "3" > /proc/sys/net/ipv4/tcp_keepalive_probes;
		echo "20" > /proc/sys/net/ipv4/tcp_keepalive_intvl;

		log -p i -t $FILE_NAME "*** TCP_TWEAKS ***: enabled";
	fi;

	if [ "$cortexbrain_tcp_ram" == on ]; then
		echo "1048576" > /proc/sys/net/core/wmem_max;
		echo "1048576" > /proc/sys/net/core/rmem_max;
		echo "262144" > /proc/sys/net/core/rmem_default;
		echo "262144" > /proc/sys/net/core/wmem_default;
		echo "20480" > /proc/sys/net/core/optmem_max;
		echo "262144 524288 1048576" > /proc/sys/net/ipv4/tcp_wmem;
		echo "262144 524288 1048576" > /proc/sys/net/ipv4/tcp_rmem;
		echo "4096" > /proc/sys/net/ipv4/udp_rmem_min;
		echo "4096" > /proc/sys/net/ipv4/udp_wmem_min;

		log -p i -t $FILE_NAME "*** TCP_RAM_TWEAKS ***: enabled";
	fi;
}
TCP_TWEAKS;

# ==============================================================
# FIREWALL-TWEAKS
# ==============================================================
FIREWALL_TWEAKS()
{
	if [ "$cortexbrain_firewall" == on ]; then
		# ping/icmp protection
		echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts;
		echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_all;
		echo "1" > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses;

		log -p i -t $FILE_NAME "*** FIREWALL_TWEAKS ***: enabled";

		return 1;
	else
		return 0;
	fi;
}
FIREWALL_TWEAKS;


# ==============================================================
# GLOBAL-FUNCTIONS
# ==============================================================

WIFI_SET()
{
	local state="$1";

	if [ "$state" == "off" ]; then
		service call wifi 13 i32 0 > /dev/null;
		svc wifi disable;
		echo "1" > $WIFI_HELPER_AWAKE;
	elif [ "$state" == "on" ]; then
		service call wifi 13 i32 1 > /dev/null;
		svc wifi enable;
	fi;

	log -p i -t $FILE_NAME "*** WIFI ***: $state";
}

WIFI()
{
	local state="$1";

	if [ "$state" == "sleep" ]; then
		if [ "$cortexbrain_auto_tweak_wifi" == on ]; then
			if [ -e /sys/module/dhd/initstate ]; then
				if [ "$cortexbrain_auto_tweak_wifi_sleep_delay" -eq "0" ]; then
					WIFI_SET "off";
				else
					(
						echo "0" > $WIFI_HELPER_TMP;
						# screen time out but user want to keep it on and have wifi
						sleep 10;
						if [ `cat $WIFI_HELPER_TMP` -eq "0" ]; then
							# user did not turned screen on, so keep waiting
							local SLEEP_TIME_WIFI=$(( $cortexbrain_auto_tweak_wifi_sleep_delay - 10 ));
							log -p i -t $FILE_NAME "*** DISABLE_WIFI $cortexbrain_auto_tweak_wifi_sleep_delay Sec Delay Mode ***";
							sleep $SLEEP_TIME_WIFI;
							if [ `cat $WIFI_HELPER_TMP` -eq "0" ]; then
								# user left the screen off, then disable wifi
								WIFI_SET "off";
							fi;
						fi;
					)&
				fi;
			else
				echo "0" > $WIFI_HELPER_AWAKE;
			fi;
		fi;
	elif [ "$state" == "awake" ]; then
		if [ "$cortexbrain_auto_tweak_wifi" == on ]; then
			echo "1" > $WIFI_HELPER_TMP;
			if [ `cat $WIFI_HELPER_AWAKE` -eq "1" ]; then
				WIFI_SET "on";
			fi;
		fi;
	fi;
}

MOBILE_DATA_SET()
{
	local state="$1";

	if [ "$state" == "off" ]; then
		svc data disable;
		echo "1" > $MOBILE_HELPER_AWAKE;
	elif [ "$state" == "on" ]; then
		svc data enable;
	fi;

	log -p i -t $FILE_NAME "*** MOBILE DATA ***: $state";
}

MOBILE_DATA_STATE()
{
	DATA_STATE_CHECK=0;

	if [ $DUMPSYS_STATE -eq "1" ]; then
		local DATA_STATE=`echo "$TELE_DATA" | awk '/mDataConnectionState/ {print $1}'`;

		if [ "$DATA_STATE" != "mDataConnectionState=0" ]; then
			DATA_STATE_CHECK=1;
		fi;
	fi;
}

MOBILE_DATA()
{
	local state="$1";

	if [ "$cortexbrain_auto_tweak_mobile" == on ]; then
		if [ "$state" == "sleep" ]; then
			MOBILE_DATA_STATE;
			if [ "$DATA_STATE_CHECK" -eq "1" ]; then
				if [ "$cortexbrain_auto_tweak_mobile_sleep_delay" -eq "0" ]; then
					MOBILE_DATA_SET "off";
				else
					(
						echo "0" > $MOBILE_HELPER_TMP;
						# screen time out but user want to keep it on and have mobile data
						sleep 10;
						if [ `cat $MOBILE_HELPER_TMP` -eq "0" ]; then
							# user did not turned screen on, so keep waiting
							local SLEEP_TIME_DATA=$(( $cortexbrain_auto_tweak_mobile_sleep_delay - 10 ));
							log -p i -t $FILE_NAME "*** DISABLE_MOBILE $cortexbrain_auto_tweak_mobile_sleep_delay Sec Delay Mode ***";
							sleep $SLEEP_TIME_DATA;
							if [ `cat $MOBILE_HELPER_TMP` -eq "0" ]; then
								# user left the screen off, then disable mobile data
								MOBILE_DATA_SET "off";
							fi;
						fi;
					)&
				fi;
			else
				echo "0" > $MOBILE_HELPER_AWAKE;
			fi;
		elif [ "$state" == "awake" ]; then
			echo "1" > $MOBILE_HELPER_TMP;
			if [ `cat $MOBILE_HELPER_AWAKE` -eq "1" ]; then
				MOBILE_DATA_SET "on";
			fi;
		fi;
	fi;
}

LOGGER()
{
	local state="$1";
	local dev_log_sleep="/dev/log-sleep";
	local dev_log="/dev/log";

	if [ "$state" == "awake" ]; then
		if [ "$android_logger" == auto ] || [ "$android_logger" == debug ]; then
			if [ -e $dev_log_sleep ] && [ ! -e $dev_log ]; then
				mv $dev_log_sleep $dev_log
			fi;
		fi;
	elif [ "$state" == "sleep" ]; then
		if [ "$android_logger" == auto ] || [ "$android_logger" == disabled ]; then
			if [ -e $dev_log ]; then
				mv $dev_log $dev_log_sleep;
			fi;
		fi;
	fi;

	log -p i -t $FILE_NAME "*** LOGGER ***: $state";
}


BUS_THRESHOLD()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		echo "$busfreq_up_threshold" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	elif [ "$state" == "sleep" ]; then
		echo "30" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	elif [ "$state" == "wake_boost" ]; then
		echo "23" > /sys/devices/system/cpu/cpufreq/busfreq_up_threshold;
	fi;

	log -p i -t $FILE_NAME "*** BUS_THRESHOLD: $state ***";
}

VFS_CACHE_PRESSURE()
{
	local state="$1";
	local sys_vfs_cache="/proc/sys/vm/vfs_cache_pressure";

	if [ -e $sys_vfs_cache ]; then
		if [ "$state" == "awake" ]; then
			echo "50" > $sys_vfs_cache;
		elif [ "$state" == "sleep" ]; then
			echo "10" > $sys_vfs_cache;
		fi;

		log -p i -t $FILE_NAME "*** VFS_CACHE_PRESSURE: $state ***";

		return 0;
	fi;

	return 1;
}



# ==============================================================
# ECO-TWEAKS
# ==============================================================
ECO_TWEAKS()
{
	if [ "$cortexbrain_eco" == on ]; then
		local LEVEL=`cat /sys/class/power_supply/battery/capacity`;
		if [ "$LEVEL" -le "$cortexbrain_eco_level" ]; then
			CPU_GOV_TWEAKS "sleep";

			log -p i -t $FILE_NAME "*** AWAKE: ECO-Mode ***";
		else
			CPU_GOV_TWEAKS "awake";

			log -p i -t $FILE_NAME "*** AWAKE: Normal-Mode ***";
		fi;

		log -p i -t $FILE_NAME "*** ECO_TWEAKS ***: enabled";
	else
		CPU_GOV_TWEAKS "awake";

		log -p i -t $FILE_NAME "*** ECO_TWEAKS ***: disabled";
		log -p i -t $FILE_NAME "*** AWAKE: Normal-Mode ***";
	fi;
}

CENTRAL_CPU_FREQ()
{
	local state="$1";

	if [ "$cortexbrain_cpu" == on ]; then

		if [ "$state" == "wake_boost" ] && [ "$wakeup_boost" -ge "0" ]; then
			echo "$scaling_max_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
			echo "$scaling_max_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			
		elif [ "$state" == "awake_normal" ]; then
			echo "$scaling_max_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
			echo "$scaling_min_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;

		elif [ "$state" == "standby_freq" ]; then
			echo "$standby_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;

		elif [ "$state" == "sleep_freq" ]; then
			echo "$scaling_min_suspend_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;
			echo "$scaling_max_suspend_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;

		elif [ "$state" == "sleep_call" ]; then
			echo "$standby_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq;

			# brain cooking prevention during call
			echo "1400000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
		fi;

		log -p i -t $FILE_NAME "*** CENTRAL_CPU_FREQ: $state ***: done";
	else
		log -p i -t $FILE_NAME "*** CENTRAL_CPU_FREQ: NOT CHANGED ***: done";
	fi;
}

# boost CPU power for fast and no lag wakeup
MEGA_BOOST_CPU_TWEAKS()
{
	if [ "$cortexbrain_cpu" == on ]; then
		CENTRAL_CPU_FREQ "wake_boost";

		log -p i -t $FILE_NAME "*** MEGA_BOOST_CPU_TWEAKS ***";
	else
		echo "$scaling_max_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq;
	fi;
}

BOOST_DELAY()
{
	# check if ROM booting now, then don't wait - creation and deletion of $DATA_DIR/booting @> /sbin/ext/post-init.sh
	if [ "$wakeup_boost" -gt "0" ] && [ ! -e $DATA_DIR/booting ]; then
		log -p i -t $FILE_NAME "*** BOOST_DELAY: ${wakeup_boost}sec ***";
		sleep $wakeup_boost;
	fi;
}

# set swappiness in case that no root installed, and zram used or disk swap used
SWAPPINESS()
{
	local SWAP_CHECK=`free | grep Swap | awk '{ print $2 }'`;

	if [ "$SWAP_CHECK" -eq "0" ]; then
		echo "0" > /proc/sys/vm/swappiness;
	else
		echo "$swappiness" > /proc/sys/vm/swappiness;
	fi;

	log -p i -t $FILE_NAME "*** SWAPPINESS: $swappiness ***";
}
SWAPPINESS;

# disable/enable ipv6  
IPV6()
{
	local state='';

	if [ -e /data/data/com.cisco.anyconnec* ]; then
		local CISCO_VPN=1;
	else
		local CISCO_VPN=0;
	fi;

	if [ "$cortexbrain_ipv6" == on ] || [ "$CISCO_VPN" -eq "1" ]; then
		echo "0" > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6;
		sysctl -w net.ipv6.conf.all.disable_ipv6=0 > /dev/null;
		local state="enabled";
	else
		echo "1" > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6;
		sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null;
		local state="disabled";
	fi;

	log -p i -t $FILE_NAME "*** IPV6 ***: $state";
}

NET()
{
	local state="$1";

	if [ "$state" == "awake" ]; then
		echo "3" > /proc/sys/net/ipv4/tcp_keepalive_probes; # default: 3
		echo "1200" > /proc/sys/net/ipv4/tcp_keepalive_time; # default: 7200s
		echo "10" > /proc/sys/net/ipv4/tcp_keepalive_intvl; # default: 75s
		echo "10" > /proc/sys/net/ipv4/tcp_retries2; # default: 15
	elif [ "$state" == "sleep" ]; then
		echo "2" > /proc/sys/net/ipv4/tcp_keepalive_probes;
		echo "300" > /proc/sys/net/ipv4/tcp_keepalive_time;
		echo "5" > /proc/sys/net/ipv4/tcp_keepalive_intvl;
		echo "5" > /proc/sys/net/ipv4/tcp_retries2;
	fi;

	log -p i -t $FILE_NAME "*** NET ***: $state";
}

# if crond used, then give it root perent - if started by STweaks, then it will be killed in time
CROND_SAFETY()
{
	if [ "$crontab" == on ]; then
		pkill -f "crond";
		/res/crontab_service/service.sh;

		log -p i -t $FILE_NAME "*** CROND_SAFETY ***";

		return 1;
	else
		return 0;
	fi;
}


IO_SCHEDULER()
{
	if [ "$cortexbrain_io" == on ]; then

		local state="$1";
		local sys_mmc0_scheduler_tmp="/sys/block/mmcblk0/queue/scheduler";
		local sys_mmc1_scheduler_tmp="/sys/block/mmcblk1/queue/scheduler";
		local tmp_scheduler="";
		local new_scheduler="";

		if [ -e $sys_mmc1_scheduler_tmp ]; then
			sys_mmc1_scheduler_tmp="/dev/null";
		fi;

		if [ "$state" == "awake" ]; then
			new_scheduler=$scheduler;
		elif [ "$state" == "sleep" ]; then
			new_scheduler=$sleep_scheduler
		fi;

		tmp_scheduler=`cat $sys_mmc0_scheduler_tmp`;

		if [ "$tmp_scheduler" != "$new_scheduler" ]; then
			echo "$new_scheduler" > $sys_mmc0_scheduler_tmp;
			echo "$new_scheduler" > $sys_mmc1_scheduler_tmp;
		fi;

		log -p i -t $FILE_NAME "*** IO_SCHEDULER: $state - $new_scheduler ***: done";

		# set I/O Tweaks again ...
		IO_TWEAKS;
	else
		log -p i -t $FILE_NAME "*** Cortex IO_SCHEDULER: Disabled ***";
	fi;
}

CPU_GOVERNOR()
{
	local state="$1";
	local scaling_governor_tmp="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor";
	local tmp_governor=`cat $scaling_governor_tmp`;

	if [ "$cortexbrain_cpu" == on ]; then
		if [ "$state" == "awake" ]; then
			if [ "$tmp_governor" != $scaling_governor ]; then
				echo "$scaling_governor" > $scaling_governor_tmp;
			fi;
		elif [ "$state" == "sleep" ]; then
			if [ "$tmp_governor" != $scaling_governor_sleep ]; then
				echo "$scaling_governor_sleep" > $scaling_governor_tmp;
			fi;
		fi;

		local USED_GOV_NOW=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`;

		log -p i -t $FILE_NAME "*** CPU_GOVERNOR: set $state GOV $USED_GOV_NOW ***: done";
	else
		log -p i -t $FILE_NAME "*** CPU_GOVERNOR: NO CHANGED ***: done";
	fi;
}


CALL_STATE()
{
	if [ "$DUMPSYS_STATE" -eq "1" ]; then

		# check the call state, not on call = 0, on call = 2
		local state_tmp=`echo "$TELE_DATA" | awk '/mCallState/ {print $1}'`;

		if [ "$state_tmp" != "mCallState=0" ]; then
			NOW_CALL_STATE=1;
		else
			NOW_CALL_STATE=0;
		fi;

		log -p i -t $FILE_NAME "*** CALL_STATE: $NOW_CALL_STATE ***";
	else
		NOW_CALL_STATE=0;
	fi;
}

#VIBRATE_FIX()
#{
#	echo "$pwm_val" > /sys/vibrator/pwm_val;

#	log -p i -t $FILE_NAME "*** VIBRATE_FIX: $pwm_val ***";
#}

# ==============================================================
# TWEAKS: if Screen-ON
# ==============================================================
AWAKE_MODE()
{
	# Do not touch this
	CALL_STATE;
#	VIBRATE_FIX;


	# Check call state, if on call dont sleep
	if [ "$NOW_CALL_STATE" -eq "1" ]; then
		CENTRAL_CPU_FREQ "awake_normal";
		NOW_CALL_STATE=0;
	else
		# not on call, check if was powerd by USB on sleep, or didnt sleep at all
		if [ "$WAS_IN_SLEEP_MODE" -eq "1" ] && [ "$USB_POWER" -eq "0" ]; then
			CPU_GOVERNOR "awake";
			LOGGER "awake";
			BUS_THRESHOLD "wake_boost";
			KERNEL_TWEAKS "awake";
			NET "awake";
			MOBILE_DATA "awake";
			WIFI "awake";
			MEGA_BOOST_CPU_TWEAKS;
			IO_SCHEDULER "awake";
			BOOST_DELAY;
			ENTROPY "awake";
			VFS_CACHE_PRESSURE "awake";
			CENTRAL_CPU_FREQ "awake_normal";
			BUS_THRESHOLD "awake";
			ECO_TWEAKS;
		else
			# Was powered by USB, and half sleep
			MEGA_BOOST_CPU_TWEAKS;
			BOOST_DELAY;
			BATTERY_TWEAKS;
			CENTRAL_CPU_FREQ "awake_normal";
			ECO_TWEAKS;
			USB_POWER=0;

			log -p i -t $FILE_NAME "*** USB_POWER_WAKE: done ***";
		fi;
		#Didn't sleep, and was not powered by USB
	fi;
}

# ==============================================================
# TWEAKS: if Screen-OFF
# ==============================================================
SLEEP_MODE()
{
	WAS_IN_SLEEP_MODE=0;

	# we only read the config when the screen turns off ...
	PROFILE=`cat $DATA_DIR/.active.profile`;
	. $DATA_DIR/${PROFILE}.profile;

	# we only read tele-data when the screen turns off ...
	if [ "$DUMPSYS_STATE" -eq "1" ]; then
		TELE_DATA=`dumpsys telephony.registry`;
	fi;

	# Check call state
	CALL_STATE;

	# Check Early Wakeup
	local TMP_EARLY_WAKEUP=`cat /tmp/early_wakeup`;

	# check if early_wakeup, or we on call
	if [ "$TMP_EARLY_WAKEUP" -eq "0" ] && [ "$NOW_CALL_STATE" -eq "0" ]; then
		WAS_IN_SLEEP_MODE=1;
		CENTRAL_CPU_FREQ "standby_freq";
		BATTERY_TWEAKS;
		CROND_SAFETY;
		SWAPPINESS;

		# for devs use, if debug is on, then finish full sleep with usb connected
		if [ "$android_logger" == debug ]; then
			CHARGING="Discharging";
		else
			CHARGING=`cat /sys/class/power_supply/Battery/status`;
		fi;

		# check if we powered by USB, if not sleep
		if [ "$CHARGING" == "Discharging" ]; then
			CPU_GOVERNOR "sleep";
			CENTRAL_CPU_FREQ "sleep_freq";
			CPU_GOV_TWEAKS "sleep";
			IO_SCHEDULER "sleep";
			BUS_THRESHOLD "sleep";

			ENTROPY "sleep";
			NET "sleep";
			WIFI "sleep";
			MOBILE_DATA "sleep";
			IPV6;

			VFS_CACHE_PRESSURE "sleep";
			KERNEL_TWEAKS "sleep";

			log -p i -t $FILE_NAME "*** SLEEP mode ***";

			LOGGER "sleep";
		else
			# Powered by USB
			USB_POWER=1;
			log -p i -t $FILE_NAME "*** SLEEP mode: USB CABLE CONNECTED! No real sleep mode! ***";
		fi;
	else
		# Check if on call
		if [ "$NOW_CALL_STATE" -eq "1" ]; then
			CENTRAL_CPU_FREQ "sleep_call";
	
			NOW_CALL_STATE=1;

			log -p i -t $FILE_NAME "*** on call: SLEEP aborted! ***";
		else
			# Early Wakeup detected
			log -p i -t $FILE_NAME "*** early wake up: SLEEP aborted! ***";
		fi;
	fi;

	# kill wait_for_fb_wake generated by /sbin/ext/wakecheck.sh
	pkill -f "cat /sys/power/wait_for_fb_wake"
}

# ==============================================================
# Background process to check screen state
# ==============================================================

# Dynamic value do not change/delete
cortexbrain_background_process=1;

if [ "$cortexbrain_background_process" -eq "1" ] && [ `pgrep -f "cat /sys/power/wait_for_fb_sleep" | wc -l` -eq "0" ] && [ `pgrep -f "cat /sys/power/wait_for_fb_wake" | wc -l` -eq "0" ]; then
	(while [ 1 ]; do
		# AWAKE State. all system ON
		cat /sys/power/wait_for_fb_wake > /dev/null 2>&1;
		AWAKE_MODE;
		sleep 2;

		# SLEEP state. All system to power save
		cat /sys/power/wait_for_fb_sleep > /dev/null 2>&1;
		sleep 2;
		/system/xbin/ext/wakecheck.sh;
		SLEEP_MODE;
	done &);
else
	if [ "$cortexbrain_background_process" -eq "0" ]; then
		echo "Cortex background disabled!"
	else
		echo "Cortex background process already running!";
	fi;
fi;

# ==============================================================
# Logic Explanations
#
# This script will manipulate all the system / cpu / battery behavior
# Based on chosen STWEAKS profile+tweaks and based on SCREEN ON/OFF state.
#
# When User select battery/default profile all tuning will be toward battery save.
# But user loose performance -20% and get more stable system and more battery left.
#
# When user select performance profile, tuning will be to max performance on screen ON.
# When screen OFF all tuning switched to max power saving. as with battery profile,
# So user gets max performance and max battery save but only on screen OFF.
#
# This script change governors and tuning for them on the fly.
# Also switch on/off hotplug CPU core based on screen on/off.
# This script reset battery stats when battery is 100% charged.
# This script tune Network and System VM settings and ROM settings tuning.
# This script changing default MOUNT options and I/O tweaks for all flash disks and ZRAM.
#
# TODO: add more description, explanations & default vaules ...
#