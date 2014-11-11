#!/bin/bash

today() {
    date +%Y%m%d
}
exit_if_error() {
    if (($?)); then echo "$1" ;exit 1; fi
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


tomcat=$1
service_files=$2
backup=$3
echo "$tomcat+$service_files+$backup"
if [ ${tomcat:+x} ]; then
    cd $tomcat
    if [ ${service_files:+x} ]; then
			backup=${backup:-"$tomcat/backup"}	

			#arr=(${service_files//|/ })
            for service_name in $(split "|" $service_files)
            do
                bname=$service_name"_"$(today)
                echo "bname:$bname"
                if [ $service_name = "qkmusic" ]; then
					echo "cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes"
                    cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes
					cp ${backup}/$bname/WEB-INF/classes/common.properties $tomcat/webapps/$service_name/WEB-INF/classes
                    exit_if_error "cp file error"
                fi
                if [ $service_name = "qkservice" ]; then
					echo "cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes"
                    cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes
                    exit_if_error "cp file error"
					echo "cp ${backup}/$bname/WEB-INF/classes/conf/spring-schedule.xml \
						$tomcat/webapps/$service_name/WEB-INF/classes/conf"
                    cp ${backup}/$bname/WEB-INF/classes/conf/spring-schedule.xml $tomcat/webapps/$service_name/WEB-INF/classes/conf

                    exit_if_error "cp file error"
                fi
				
				if [ $service_name = "qkcheck" ]; then
					echo "cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes"
					cp ${backup}/$bname/WEB-INF/classes/jdbc.properties $tomcat/webapps/$service_name/WEB-INF/classes
					exit_if_error "cp file error"
				fi

            done

    fi
fi
