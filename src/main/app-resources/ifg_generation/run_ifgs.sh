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
ERR_STEP_COARSE=13
ERR_STEP_COREG=15
ERR_STEP_DEM=17
ERR_STEP_RESAMPLE=19
ERR_STEP_IFG=21
ERR_INSAR_SLAVES_TAR=23
ERR_INSAR_SLAVES_PUBLISH=25
ERR_FINAL_PUBLISH=27

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_MASTER_RETRIEVE}) msg="Failed to retrieve Master folder";;
${ERR_DEM_RETRIEVE}) msg="Failed to retrieve DEM folder";;
${ERR_SLC_RETRIEVE}) msg="Failed to retrieve SLC folder";;
${ERR_STEP_COARSE}) msg="Failed to do coarse image correlation";;
${ERR_STEP_COREG}) msg="Failed to do fine image correlation";;
${ERR_STEP_DEM}) msg="Failed to do simulate amplitude";;
${ERR_STEP_RESAMPLE}) msg="Failed to resample image";;
${ERR_STEP_IFG}) msg=" Failed to create IFG";;
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
master_date=""

while read line; do

	ciop-log "INFO" "Processing input: $line"
        
done

}
cat | main
exit ${SUCCESS}
