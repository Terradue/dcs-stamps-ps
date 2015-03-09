#! /bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# source sar helpers and functions
set_env

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_PREMASTER=5

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_PREMASTER}) msg="couldn't retrieve ";; 

esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
#[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ -n "${TMPDIR}" ] && chmod -R 777 $TMPDIR
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

main() {
local res

while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master slc_folders <<< "$line"

	if [ ! -d ${PROCESS}/INSAR_$master_date/ ]; then
		ciop-copy -O ${PROCESS} ${insar_master}
		[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
		master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Final Master Date: $master_date"

		cd ${PROCESS}	
		tar xvfz INSAR_${master_date}.tgz 
		[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

		cd INSAR_${master_date}
		
	fi

	ciop-copy -O ${SLC} ${slc_folders}
	[ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}


	if [ $sensing_date != $premaster_date ];then
		
		cd ${PROCESS}/INSAR_${premaster_date}
		mkdir ${sensing_date}
		cd ${sensing_date}

		# step_orbit (extract orbits)
		ln -s ${SLC}/${sensing_date} SLC
		ciop-log "INFO" "step_orbit for ${sensing_date} "
		step_orbit
		[ $? -ne 0 ] && return ${ERR_STEP_ORBIT}
	
		####sed for coarse.dorisin####
		ciop-log "INFO" "doing image coarse correlation for ${sensing_date}"
		
		cp $DORIS_SCR/coarse.dorisin
		sed 
		doris coarse.dorisin > step_coarse.log
		[ $? -ne 0 ] && return ${ERR_STEP_COARSE}

		# make sure that in Stamps/DORIS_SCR
		#	get all calculated coarse offsets (line 85 - 184) and take out the value which appears most
		offsetL=`more coreg.out | sed -n -e 85,184p | awk $'{print $5}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`
		offsetP=`more coreg.out | sed -n -e 85,184p | awk $'{print $6}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`

		# 	write the lines with the new overall offset into variable	 
		replaceL=`echo -e "Coarse_correlation_translation_lines: \t" $offsetL`
		replaceP=`echo -e "Coarse_correlation_translation_pixels: \t" $offsetP`	

		# 	replace full line of overall offset
		sed -i "s/Coarse_correlation_translation_lines:.*/$replaceL/" coreg.out
		sed -i "s/Coarse_correlation_translation_pixels:.*/$replaceP/" coreg.out

		ciop-log "INFO" "doing image fine correlation for ${sensing_date}"
		step_coreg
		[ $? -ne 0 ] && return ${ERR_STEP_COREG}

		ciop-log "INFO" "doing image simamp for ${sensing_date}"
		step_dem
		[ $? -ne 0 ] && return ${ERR_STEP_DEM}

		ciop-log "INFO" "doing resample for ${sensing_date}"
		step_resample
		[ $? -ne 0 ] && return ${ERR_STEP_RESAMPLE}

		ciop-log "INFO" "doing ifg generation for ${sensing_date}"
		step_ifg
		[ $? -ne 0 ] && return ${ERR_STEP_IFG}

		cd ../
        	ciop-log "INFO" "create tar"
        	tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}
        	[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

		ciop-log "INFO" "Publish -a insar_slaves"
		insar_slaves="$( ciop-publish -a ${SLC}/${sensing_date}.tgz )"
	
	else
		insar_slaves=""
	fi 

	
	# substitute file in master.res & slave.res 

