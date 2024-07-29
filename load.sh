#!/bin/bash

#Vars

SETTINGS=$HOME/.config/load.env
SCRIPT=$HOME/bin/load.sh
URL="https://raw.githubusercontent.com/sshamanov/load_script/main/load.sh"
OPTIONS='Please run with $0 install [-c|--cpu 0-100] [-m|--mem 0-100] [-d|--hdd 0-100]'
HDDPATH="$HOME/temp-hdd-load"

#Functions

value ()
{
	if echo $2 | grep -q -E "^[0-9]+-[0-9]+$" ; then
		if [ $1 = min ]; then
			echo $(echo $2 | awk -F - '{print$1}')
		elif [ $1 = max ]; then
                        echo $(echo $2 | awk -F - '{print$2}')
		else
			exit 1
		fi
	elif echo $2 | grep -q -E "^[0-9]+$" ; then
		echo $2
	else
		echo "Faild to parse values!"
                echo "Please enter value using format MIN-MAX or CUR"
                echo "Where MIN, MAX or CUR percent values without % sign"
                exit 1
	fi
}

parse_settings()
{
	test $# -gt 2 || (
		echo "Empty settings"
		echo $OPTIONS
		exit 1 )

	while [[ $# -gt 2 ]]; do
		case $2 in
			-c|--cpu)
				CPU0=$(value min $3)
				CPU1=$(value max $3)
				shift
				shift
				;;
			-m|--mem)
				MEM0=$(value min $3)
				MEM1=$(value max $3)
				shift
				shift
				;;
			-d|--hdd)
				HDD0=$(value min $3)
				HDD1=$(value max $3)
				shift
				shift
				;;
			*)
				echo "Unknown options!"
				echo $OPTIONS
				exit 1
				;;
		esac
	done
}

save_settings()
{
	cat <<EOF > $SETTINGS
CPU0=$CPU0
CPU1=$CPU1
MEM0=$MEM0
MEM1=$MEM1
HDD0=$HDD0
HDD1=$HDD1
EOF
}

save_scheduler()
{
	crontab -u $USER -r
	echo "* * * * * $SCRIPT run > /dev/null" | crontab -u $USER -
	
}

install_script()
{
	which stress-ng > /dev/null || ( sudo apt update ; sudo apt -y install stress-ng )
	which wget > /dev/null || ( sudo apt update ; sudo apt -y wget )
	mkdir -p $HOME/bin
	test -x $SCRIPT || wget $URL -O $SCRIPT
}

rund_val()
{
	VAL0=$1
	VAL1=$2
	if [ ! -z $VAL0 ] && [ ! -z $VAL1 ] && [ $VAL1 -gt $VAL0 ] ; then
                VAL=$(( VAL0 + RANDOM % (VAL1 - VAL0) ))
        else
                VAL=$VAL0
        fi
}

run()
{
	echo "Load settings..."
	. $SETTINGS

	rund_val $HDD0 $HDD1
	HDD=$VAL

	rund_val $CPU0 $CPU1
	CPU=$VAL

	rund_val $MEM0 $MEM1
	MEM=$VAL

	if [ ! -z $HDD ] ; then
		echo "Starting HDD load with $HDD%..."
		hdd_task &
	fi

	if [ ! -z $CPU ] && [ -z $MEM ] ; then
                echo "Starting CPU load with $CPU%..."
		cpu_task &
        fi

        if [ ! -z $MEM ] && [ -z $CPU ] ; then
                echo "Starting MEM load with $MEM%..."
		mem_task &
        fi

        if [ ! -z $CPU ] && [ ! -z $MEM ] ; then
                echo "Starting CPU load with $CPU%..."
                echo "Starting MEM load with $MEM%..."
		cpu_mem_task &
        fi
}

hdd_task(){
	rm -rf $HDDPATH/file*
	mkdir -p $HDDPATH
	until [ $(df / | tail -n1 | awk '{print$5}' | tr -d %) -gt $((HDD - 1)) ] ; do
		fallocate --length 1G $HDDPATH/file.$((1 + RANDOM % 1000))
	done
}

cpu_val(){
	VAL=$((CPU * $(getconf _NPROCESSORS_ONLN)))
}

cpu_task(){
	stress-ng --cpu $(getconf _NPROCESSORS_ONLN) --cpu-load $CPU --timeout 60
}

mem_task(){
	systemd-run --scope -p CPUQuota=50% stress-ng --vm 1 --vm-keep --vm-bytes $MEM% --timeout 60
}

cpu_mem_task(){
	systemd-run --scope -p CPUQuota=$((CPU * $(getconf _NPROCESSORS_ONLN)))% stress-ng --cpu $(getconf _NPROCESSORS_ONLN) --vm 1 --vm-keep --vm-bytes $MEM% --timeout 60
}

# Start from here

if [ ! -f $SETTINGS ] ; then
	echo "First run."
	echo "Empty config!"
	echo $OPTIONS
	exit 1
fi

# Commands

case $1 in
	install)
		echo "Instaling..."
		install_script
		parse_settings $@
		save_settings
		save_scheduler
		echo "Instlled with setings:"
		cat $SETTINGS
		;;
	run|start)
		echo "Starting..."
		run
		;;
	delete|remove|stop|disable)
		echo "Deleting schedule..."
		crontab -u $USER -r
		;;
	*)
		echo "Unknown command!"
		echo "Please use $0 [install|run|delete] [options]"
		exit 1
		;;
esac
