#! /bin/bash
mode=$1
#set -x 

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
ERR_MASTER_RETRIEVE=7
ERR_UNTAR_MASTER=9
ERR_SLC_RETRIEVE=11


# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_MASTER_RETRIEVE}) msg="";;
${ERR_UNTAR_MASTER}) msg="";;
${ERR_SLC_RETRIEVE}) msg="";;
${ERR_STEP_ORBIT}) msg="";;
${ERR_MASTER_RETRIEVE}) msg="";;
${ERR_MASTER_RETRIEVE}) msg="";;
${ERR_MASTER_RETRIEVE}) msg="";;
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
master_date=""

while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master slc_folders dem <<< "$line"
	ciop-log "DEBUG" "1:$insar_master 2:$slc_folders 3:$dem"

	if [ ! -d ${PROCESS}/INSAR_$master_date/ ]; then
	
		ciop-copy -O ${PROCESS} ${insar_master}
		[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
		master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Final Master Date: $master_date"
		
	fi

	if [ ! ${TMPDIR}/DEM/final_dem.dem ]; then

	ciop-copy -O ${TMPDIR} ${dem}
	[ $? -ne 0 ] && return ${ERR_DEM_RETRIEVE}

	fi

	ciop-copy -O ${SLC} ${slc_folders}
	[ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}
	
	sensing_date=`basename ${slc_folders} | cut -c 1-8`
	

	ciop-log "INFO" "Processing scene of $sensing_date"
	
done
}
cat | main
exit ${SUCCESS}

