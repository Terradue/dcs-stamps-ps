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

# source MCR 
MCR="/usr/local/MATLAB/MATLAB_Compiler_Runtime/v717"

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_MASTER_RETRIEVE=7
ERR_DEM_RETRIEVE=9
ERR_INSAR_SLAVE_RETRIEVE=11
ERR_STEP_GEO=13
ERR_MT_PREP=15
ERR_STAMPS_1=17
ERR_INSAR_TAR=19
ERR_INSAR_PUBLISH=21
ERR_PATCH_TAR=23
ERR_PATCH_PUBLISH=25
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
${ERR_INSAR_SLAVE_RETRIEVE}) msg="Failed to tar Insar Slave folder";;
${ERR_STEP_GEO}) msg="Failed to geoference the image stack";; 
${ERR_MT_PREP}) msg="Failed to run mt_prep routine";;
${ERR_STAMPS_1}) msg="Failed to process step 1 of StaMPS";;
${ERR_INSAR_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_INSAR_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_PATCH_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_PATCH_PUBLISH}) msg="Failed to publish Insar Slave folder";;
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
        IFS=',' read -r insar_master sinsar_slaves <<< "$line"
	ciop-log "DEBUG" "1:$insar_master 2:$insar_slaves 3:$dem"

    	if [ ! -d "${PROCESS}/INSAR_${master_date}/" ]; then
	
	ciop-log "INFO" "Retrieving Master folder"
	ciop-copy -O ${PROCESS} ${insar_master}
	[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
	master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
	ciop-log "INFO" "Final Master Date: $master_date"
		
	fi

	if [ ! -e "${TMPDIR}/DEM/final_dem.dem" ]; then

	ciop-log "INFO" "Retrieving DEM folder"
	ciop-copy -O ${TMPDIR} ${dem}
	[ $? -ne 0 ] && return ${ERR_DEM_RETRIEVE}

	fi
	
	ciop-log "INFO" "Retrieving SLC folder"
	ciop-copy -O ${PROCESS}/INSAR_${master_date} ${insar_slaves}
	[ $? -ne 0 ] && return ${ERR_INSAR_SLAVE_RETRIEVE}


	ciop-log "INFO" "Georeferencing image stack"
 	first_folder=`ls -d -1 2*/`
	cd ${PROCESS}/INSAR_${master_date}/$first_folder
	step_geo 
	[ $? -ne 0 ] && return ${ERR_STEP_GEO}

done

ciop-log "INFO" "running mt_prep to load dta ino matlab variables"
cd ${PROCESS}/INSAR_${master_date}/
mt_prep 0.42 4 5 50 200
[ $? -ne 0 ] && return ${ERR_MT_PREP}

# Check for size of pscands.1.da to see if enough PS are contained
rm patch.list
ls -1 -s */pscands.1.da > patch_size.txt
while read line; do
 	PATCH_SIZE=`echo $line | awk $'{print $ 1}'`
	if [[ "${PATCH_SIZE}" -gt "100" ]] ; then
		VALID_PATCHES=`echo $line | awk $'{print $2}' | awk -F '/' $'{print $1}'`
		echo $VALID_PATCHES >> patch.list
	fi
done < patch_size.txt

ciop-log "INFO" "Running Stamps step 1"
/opt/StaMPS_v3.3b1/matlab/stamps $MCR 1 1
[ $? -ne 0 ] && return ${ERR_STAMPS_1}

ciop-log "INFO" "creating tar for InSAR Master folder"
tar cvfz INSAR_${master_date}.tgz *.txt *.out *.res *.in *.m *.mat patch.list
[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

ciop-log "INFO" "publishing InSAR Master folder"
insar_master="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}.tgz )"
[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}

while read line; do

	ciop-log "INFO" "Tar $line"
	tar cvfz $line.tgz $line
	[ $? -ne 0 ] && return ${ERR_PATCH_TAR}
	
	ciop-log "INFO" "publishing $line"
	patches="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}/$line.tgz )"
	[ $? -ne 0 ] && return ${ERR_PATCH_PUBLISH}

	ciop-log "INFO" "publishing the final output"
	echo "${insar_master},${patches}" | ciop-publish -s	
	[ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}


done < patch.list

}
cat | main
exit ${SUCCESS}

