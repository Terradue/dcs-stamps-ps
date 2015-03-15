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
ERR_DEM_RETRIEVE=9
ERR_SLC_RETRIEVE=11

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_MASTER_RETRIEVE}) msg="Failed to retrieve Master folder";;
${ERR_DEM_RETRIEVE}) msg="Failed to retrieve DEM folder";;
${ERR_SLC_RETRIEVE) msg="Failed to retrieve SLC folder";;


${ERR_INSAR_SLAVES_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_INSAR_SLAVES_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_FINAL_PUBLISH}) msg="Failed to publish all output together";;
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
#	master_date=""
first=TRUE


while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master slc_folders dem <<< "$line"
	ciop-log "DEBUG" "1:$insar_master 2:$insar_slaves 3:$dem"

[ ${first} == "TRUE" ] && {
     
#	if [ ! -d "${PROCESS}/INSAR_${master_date}/" ]; then
	
	ciop-log "INFO" "Retrieving Master folder"
	ciop-copy -O ${PROCESS} ${insar_master}
	[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
	master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
	ciop-log "INFO" "Final Master Date: $master_date"
		
#	fi

#	if [ ! -e "${TMPDIR}/DEM/final_dem.dem" ]; then

	ciop-log "INFO" "Retrieving DEM folder"
	ciop-copy -O ${TMPDIR} ${dem}
	[ $? -ne 0 ] && return ${ERR_DEM_RETRIEVE}

#	fi

	ciop-log "INFO" "Retrieving SLC folder"
	ciop-copy -O ${PROCESS}/INSAR_${master_date} ${insar_slaves}
	[ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}

	ciop-log "INFO" "Georeferencing image stack"
 	first_folder=`ls -d -1 2*/`
	cd ${PROCESS}/INSAR_${master_date}/$first_folder
	step_geo 
	[ $? -ne 0 ] && return ${ERR_STEP_GEO}
    	}

	first=FALSE	
done

ciop-log "INFO" "running mt_prep to load dta ino matlab variables"
cd ${PROCESS}/INSAR_${master_date}/
mt_prep 0.42 4 5 50 200
[ $? -ne 0 ] && return ${ERR_MT_PREP}


tar cvfz INSAR_${master_date}.tgz *.txt *.out *.res *.in 

ls -d -1 P*

stamps(1,2)

#stamps(1,1)

