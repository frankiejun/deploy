#!/bin/bash
#author: xiejf
#date:   2014-07-01

usage() {
    echo "$0 "
    echo "[-t] [tomcat's path]"
    echo "[-b] if backups the webapps, sepcifies backup dir path"
    echo "[-s] [specify service name to update, must work with -p]"
    echo "[-p] [path of service's war, the war file in it will be udpate]"
    echo "[-r] [only restart service]"
    echo "[-o] [only stop service]"
    echo "[-x] [extent shell, run after extract war]"
    exit
}

today() {
    date +%Y%m%d
}

exit_if_error() {
    if (($?)); then echo "$1" ;exit 1; fi
}

alive() {
	local f=$1;
	local a=`ps -ef | grep "$f" | grep "java" | grep -v "grep" | awk '{print $2}'`;
	echo $a;
}

backup_file() {
    local service=$1
    date=$(today)
    bname="$service""_""$date"
	if [ -e "backup/$bname" ]; then
		rm -rf "backup/$bname"
	fi
	echo "cp -r webapps/$service backup/$bname"
    cp -r webapps/$service backup/$bname
   # exit_if_error "backup file error"
}

extract_webapp() {
    local service=$1
    local service_path=$2
    local service_name=${service%%.*}


    if [ -d webapps/$service_name ]; then
        rm -rf webapps/$service_name
        exit_if_error "rm file error"
    fi
    unzip -oq $service_path/$service -d webapps/$service_name
    exit_if_error "unzip error"
  #  rm -rf $service_path/$service
}

stop_() {
	local tomcat="$1"
	echo "shutdowning tomcat ..."
    local x=$($tomcat/bin/shutdown.sh);
    sleep 1;
	for pid in $(alive $tomcat); do
		if [ $pid = "$$" ]; then
			continue;
		fi
		echo "killing tomcat pid $pid...";
		#pkill -KILL  -u qkmusic "$tomcat"; pkill can't kill the tomcat
		kill -9 $pid;
	done
}

restart_() {
	stop_ $1
    #start service
    echo "startuping tomcat ..."
    local y=$($tomcat/bin/startup.sh);
    echo "done"
}

split() {
	local sp=$1
	local arr=$2
	local old_ifs="$IFS"
	IFS="$sp"
	for s in ${arr[@]}
	do
		echo $s
	done
	IFS=$old_ifs
}

contain_str() {
		local a=$1
		local b=$2

		local rr=$(expr  match "$a" ".*$b")
		echo $rr
}


if [ $# -lt 1 ]; then
    usage
fi

while getopts "t:b:s:p:x:ro" arg 
do
    case $arg in
        t)
            tomcat=$OPTARG
            ;;
        b)
            backup=$OPTARG
            ;;
        s)
            service=$OPTARG
            ;;
        p)
            service_path=$OPTARG
            ;;
        r)
            rst=1;
            ;;
		o)
		    _stop=1;	
			;;
        x)
            extent_shell=$OPTARG
            ;;
        ?)
            echo "unknow arg"
            exit 1
            ;;
    esac
done

excute_path=$(dirname $0);
. /etc/profile;
source ~/.bash_profile;
source ~/.bashrc;
#begin 
if  [ ${rst:+x} ] && [ -n "$tomcat" ]; then
    restart_ $tomcat
   
elif [ ${_stop:+x} ] && [ -n "$tomcat" ]; then
    stop_ $tomcat

elif [ -n "$tomcat" ] && [ -n "$service_path" ]; then
    
    cd $tomcat
	exit_if_error "cd to $tomcat error";

    #stop the service
	echo "shutdowning tomcat ..."
    x=$(/bin/bash $tomcat/bin/shutdown.sh)
    sleep 2;
	for pid in $(alive $tomcat); do
		if [ $pid = "$$" ]; then
			continue;
		fi
		echo "killing tomcat pid $pid...";
		#pkill -KILL  -u qkmusic "$tomcat"; pkill can't kill the tomcat
		kill -9 $pid;
	done

    #backup old webapps
    if [ -n $backup ]; then
        if [ ! -e "backup" ]; then
            mkdir backup
            if (($?)); then echo "mkdir backup error" ;exit 1; fi
        fi
        if [ ${service:+x} ]; then
			for file in $(split "," $service)
			do
        		backup_file $file 
			done
        else
            for file in `ls $service_path`;
            do
				service_name=${file%%.war}
                backup_file $service_name
            done

        fi
    fi
	#if not exists dir of war file, create it.
	if [ ! -e $service_path ]; then
		mkdir $service_path
	fi

    #extract webapp's files
    service_files= 
    if [ ${service:+x} ]; then
		for war in $(split "," $service)
		do
        	extract_webapp "${war}.war" $service_path
        	service_files=${service_files}"|"${war}
		done
		echo "service_files:$service_files"
    else
        for war in `ls $service_path`;
        do
            extract_webapp $war $service_path
			if [ ${service_files:+x} ]; then
            service_files=${service_files}"|"${war%%.*}
			else
				service_files=${war%%.*}
			fi
			echo "service_files:$service_files"
        done
    fi
    
    if [ ${extent_shell:+x} ]; then
		echo "/bin/bash $extent_shell $tomcat $service_files $backup >> tom.log"
        x=$(/bin/bash $extent_shell $tomcat $service_files $backup)
		echo "$x"
    fi

    #start service
    echo "startup ..."
    x=$($tomcat/bin/startup.sh)
    echo "$x"
    echo "upgrade done!"
else
    echo "must specify -t"
    exit 1
fi
