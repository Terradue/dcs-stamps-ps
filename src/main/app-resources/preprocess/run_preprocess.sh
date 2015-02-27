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
#	2) Error Handling	
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_ORBIT_FLAG=5
ERR_SCENE_EMPTY=7
ERR_SENSING_DATE=9
ERR_MISSION=11
ERR_AUX=13
ERR_LINK_RAW=15
ERR_SLC=17
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
{ERR_ORBIT_FLAG}) msg="Failed to determine which orbit files to use (check your application.xml)";;
${ERR_SCENE_EMPTY}) msg="Failed to retrieve scene";;
${ERR_SENSING_DATE}) msg="Couldn't retrieve scene sensing date";;
${ERR_MISSION}) msg="Couldn't determine the satellite mission for the scene";;
${ERR_AUX}) msg="Couldn't retrieve auxiliary files";;
${ERR_LINK_RAW}) msg="Failed to link the raw data to SLC folder";;
${ERR_SLC}) msg="Failed to focalize raw data with ROI-PAC";;
${ERR_SLC_TAR}) msg="Failed to create archive with scene";;
${ERR_SLC_PUBLISH}) msg="Failed to publish archive with slc";;
esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

#--------------------------------
#	3) Main Function	
#--------------------------------
main() {
local res

# Inputlist path
INPUT=${_CIOP_APPLICATION_PATH}/inputs/inputlist

# Folder where raw data should be stored
RAW=${TMPDIR}/RAW

# PROCESS folder
export PROCESS=${TMPDIR}/PROCESS

# create folders
mkdir -p $RAW 
mkdir -p $PROCESS

# download data into $RAW
while read line; do 
	
	# which orbits (defined in application.xml)
	orbits="$( get_orbit_flag )"
	[ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}

	ciop-log "INFO" "Retrieving scene"
	#scene=$( get_data ${line} ${RAW} )
	scene="$( ciop-copy -f -U -O ${RAW} ${line} 2> /dev/null )"
	[ $? -ne 0 ] && return ${ERR_SCENE_EMPTY}

	ciop-log "INFO" "Get sensing date"
	sensing_date=$( get_sensing_date ${scene} )
	[ $? -ne 0 ] && return ${ERR_SENSING_DATE}

	ciop-log "INFO" "Get mission"
	mission=$( get_mission ${scene} | tr "A-Z" "a-z" )
	[ $? -ne 0 ] && return ${ERR_MISSION}
	[ ${mission} == "asar" ] && flag="envi"

	get_aux ${mission} ${sensing_date} ${orbits}
	[ $? -ne 0 ] && return ${ERR_AUX}
	
	# link_raw
	ciop-log "INFO" "Set-up Stamps Structure (i.e. link_raw)"
	link_raw $RAW $PROCESS
	[ $? -ne 0 ] && return ${ERR_LINK_RAW}
	
	# focalize SLC
	scene_folder=${TMPDIR}/PROCESS/SLC/${sensing_date}
	cd ${scene_folder}	
	slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
	ciop-log "INFO" "Run ${slc_bin} for ${sensing_date}"
	${slc_bin}
	[ $? -ne 0 ] && return ${ERR_SLC}

	# publish for next node
	cd ${TMPDIR}/PROCESS/SLC
	ciop-log "INFO" "create tar"
	tar cvfz ${sensing_date}.tgz ${sensing_date}
	[ $? -ne 0 ] && return ${ERR_SLC_TAR}

	ciop-log "INFO" "Publishing"
 	ciop-publish ${TMPDIR}/PROCESS/SLC/${sensing_date}.tgz
	[ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}

done 

}
cat | main
exit ${SUCCESS}
