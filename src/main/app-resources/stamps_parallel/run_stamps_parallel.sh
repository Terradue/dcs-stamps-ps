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

MCR="/usr/local/MATLAB/MATLAB_Compiler_Runtime/v717"

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_MASTER_RETRIEVE=7
ERR_PATCH_RETRIEVE=9
ERR_STAMPS_2=13
ERR_STAMPS_3=15
ERR_STAMPS_4=17
ERR_PATCH_TAR=23
ERR_PATCH_PUBLISH=25
ERR_INSAR_TAR=19
ERR_INSAR_PUBLISH=21
ERR_FINAL_PUBLISH=27

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_MASTER_RETRIEVE}) msg="Failed to retrieve Master folder";;
${ERR_PATCH_RETRIEVE}) msg="Failed to retrieve the PATCH folder";;
${ERR_STAMPS_2}) msg="Failed to process step 2 of StaMPS";;
${ERR_STAMPS_3}) msg="Failed to process step 3 of StaMPS";;
${ERR_STAMPS_4}) msg="Failed to process step 4 of StaMPS";;
${ERR_PATCH_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_PATCH_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_INSAR_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_INSAR_PUBLISH}) msg="Failed to publish Insar Slave folder";;
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
master_date=""


while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master patches <<< "$line"
	ciop-log "DEBUG" "1:$insar_master 2:$patches"

	
        if [ ! -d "${PROCESS}/INSAR_${master_date}/" ]; then
	
		ciop-log "INFO" "Retrieving Master folder"
		ciop-copy -O ${PROCESS} ${insar_master}
		[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}		
		
		master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Final Master Date: $master_date"
	
	fi
	
	ciop-log "INFO" "Retrieving PATCH folder"
	ciop-copy -O ${PROCESS}/INSAR_${master_date} ${patches}
	[ $? -ne 0 ] && return ${ERR_PATCH_RETRIEVE}

	ciop-log "INFO" "Input directoy patches: $patches"
	patch=`basename ${patches} | rev | cut -c 5- | rev`
	ciop-log "INFO" "Processing $patch"
	
	cd ${PROCESS}/INSAR_${master_date}/$patch
	ciop-log "INFO" "StaMPS step 2: Estimate Phase noise (may take while...)"
	/opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 2 2
	[ $? -ne 0 ] && return ${ERR_STAMPS_2}

	ciop-log "INFO" "StaMPS step 3: PS Selection (may take while...)"
	/opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 3 3
	[ $? -ne 0 ] && return ${ERR_STAMPS_3}
	
	ciop-log "INFO" "StaMPS step 4: PS Weeding"
	/opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 4 4 
	res=$?; [ $res -ne 0 ] && ciop-log "WARN" "stamps 4 exited with $res for $patch (can be expected for decorrelated areas like water, forest etc.)"

	if [[ $res -eq "0" ]]; then
		
		cd ${PROCESS}/INSAR_${master_date}/
		ciop-log "INFO" "Tar $patch"
		tar cvfz $patch.tgz $patch
		[ $? -ne 0 ] && return ${ERR_PATCH_TAR}
	
		ciop-log "INFO" "publishing $patch"
		patches="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}/$patch.tgz )"
		[ $? -ne 0 ] && return ${ERR_PATCH_PUBLISH}

		rm -rf $patch

		cd ${PROCESS}/
		ciop-log "INFO" "creating tar for InSAR Master folder"
		tar cvfz INSAR_${master_date}.tgz  INSAR_${master_date}
		[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

		ciop-log "INFO" "publishing InSAR Master folder"
		insar_master="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}.tgz )"
		[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}

		ciop-log "INFO" "publishing the final output"
		echo "${insar_master},${patches}" | ciop-publish -s	
		[ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}
		
	fi

#	if [[ $res -ne "0" ]]; then
#
#		cd ${PROCESS}/INSAR_${master_date}/
#		rm -rf $patch

#	fi
done

#cd ${PROCESS}
#ciop-log "INFO" "creating tar for InSAR Master folder"
#tar cvfz INSAR_${master_date}.tgz INSAR_${master_date}
#[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

#ciop-log "INFO" "publishing the final output"
#ciop-publish ${PROCESS}/INSAR_${master_date}.tgz
#[ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}

}
cat | main
exit ${SUCCESS}
