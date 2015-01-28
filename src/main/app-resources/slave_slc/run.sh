#!/bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# define the exit codes
SUCCESS=0

# add a trap to exit gracefully
cleanExit () {
  local retval=$?
  local msg

  msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
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
      # TODO check copy
      ciop-copy -O ${SLC} ${txt_ref}
      # TODO check copy 
      first=FALSE
    }
  
  slave=$( ciop-copy -O $TMPDIR )
  
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

  cd ${_folder}
  ln -s ${slave}
  slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor")"
  ciop-log "INFO" "Run $slc_bin for ${sensing_date}"
  
  ${slc_bin}
  [ $? -ne 0 ] && return ${ERR_SLC}
  
  cd ${SLC}
  tar cvfz ${sensing_date}.tgz ${sensing_date}
  
  ciop-publish ${sensing_date}.tgz
  
  rm -fr ${SLC}/${sensing_date}
}

cat | main 
res=$?
[ ${res} -ne 0 ] && exit ${res}
  
[ "$mode" != "test" ] && exit 0
