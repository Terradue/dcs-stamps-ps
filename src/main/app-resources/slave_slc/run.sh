#!/bin/bash

mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source the stamps-helpers
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# define the exit codes
SUCCESS=0
ERR_ORBIT_FLAG=5
ERR_MASTER_SLC=7
ERR_SLC_AUX=9
ERR_SLAVE=9
ERR_SLAVE_SENSING_DATE=11
ERR_MISSION_SLAVE=13
ERR_AUX=15
ERR_SLC=17
ERR_SLC_TAR=19
ERR_SLC_PUBLISH=21

# add a trap to exit gracefully
cleanExit() {
  local retval=$?
  local msg
  msg=""

  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit files to use";;
    ${ERR_MASTER_SLC}) msg="Couldn't retrieve master slc";;
    ${ERR_SLC_AUX}) msg="Couldn't retrieve master slc ROI_PAC aux files";;
    ${ERR_SLAVE}) msg="Couldn't retrieve slave";;
    ${ERR_SLAVE_SENSING_DATE}) msg="Couldn't determine slave sensing day";;
    ${ERR_MISSION_SLAVE}) msg="Couldn't determine slave mission";;
    ${ERR_AUX}) msg="Couldn't retrieve slave aux files";;
    ${ERR_SLC}) msg="Failed to process slc";;
    ${ERR_SLC_TAR}) msg="Failed to create archive with slave slc";;
    ${ERR_SLC_PUBLISH}) msg="Failed to publish archive slave slc";;
  esac
  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}

trap cleanExit EXIT

main() {
  local res

  # creates the adore directory structure
  ciop-log "INFO" "creating the directory structure"
  set_env
  
  # which orbits
  orbits="$( get_orbit_flag )"
  [ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}
  
  first=TRUE
  
  while read master_slc_ref txt_ref slave_ref; do
  
    [ ${first} == "TRUE"] && {
      ciop-copy -O ${SLC} ${master_slc_ref}
      [ $? -ne 0 ] && return ${ERR_MASTER_SLC}
      ciop-copy -O ${SLC} ${txt_ref}
      [ $? -ne 0 ] && return ${ERR_MASTER_SLC}
      first=FALSE
    }
  
    slave=$( ciop-copy -O $TMPDIR )
    [ $? -ne 0 ] && return ${ERR_SLAVE}
  
    sensing_date=$( get_sensing_date $slave )
    [ $? -ne 0 ] && return ${ERR_SLAVE_SENSING_DATE}
  
    mission=$( get_mission ${slave} | tr "A-Z" "a-z" )
    [ $? -ne 0 ] && return ${ERR_MISSION_SLAVE}
    [ ${mission} == "asar" ] && flag="envi"
  
    # TODO manage ERS and ALOS
    # [ ${mission} == "alos" ] && flag="alos"
    # [ ${mission} == "ers" ] && flag="ers"
    # [ ${mission} == "ers_envi" ] && flag="ers_envi"
  
    slave_folder=${SLC}/${sensing_date}
    mkdir -p ${slave_folder}
  
    get_aux ${mission} ${sensing_date} ${orbits} 
    [ $? -ne 0 ] && return ${ERR_AUX}

    cd ${slave_folder}
    ln -s ${slave}
    slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor")"
    ciop-log "INFO" "Run $slc_bin for ${sensing_date}"
  
    ${slc_bin}
    [ $? -ne 0 ] && return ${ERR_SLC}
  
    cd ${SLC}
    tar cvfz ${sensing_date}.tgz ${sensing_date}
    [ $? -ne 0 ] && return ${ERR_SLC_TAR}
  
    slave_slc_ref=$( ciop-publish ${sensing_date}.tgz )
    [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}
  
    # publish the references for the next job
    echo "${master_slc_ref} ${txt_ref} ${slave_slc_ref}" | ciop-publish -s
    rm -fr ${SLC}/${sensing_date}

  done
}

cat | main 
res=$?
[ ${res} -ne 0 ] && exit ${res}
  
[ "$mode" != "test" ] && exit 0
