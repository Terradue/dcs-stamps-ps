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

set_env() {
  export SAR_HELPERS_HOME=/opt/sar-helpers/lib/
  . ${SAR_HELPERS_HOME}/sar-helpers.sh

  # shorter temp path
  export TMPDIR=/tmp/$( uuidgen )
  mkdir -p ${TMPDIR}
  return $?
}

get_data() {
  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  enclosure="$( opensearch-client "${ref}" enclosure )"
  res=?
  # opensearh client doesn't deal with local paths
  [ ${res} -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
  [ ${res} -ne 0 ] && enclosure=${ref}
  
  local_file="$( echo ${enclosure} | ciop-copy -f -U -O ${target} - 2> /dev/null )"
  res=$?
  [ ${res} -ne 0 ] && return ${res}
  echo ${local_file}
}

get_orbit_flag() {

}

get_aux() {
  
}

main() {
  local res

  # creates the adore directory structure
  ciop-log "INFO" "creating the directory structure"
  set_env
  
  # which orbits
  orbits="$( get_orbit_flag )"

  master_ref="$( ciop-getparam master )"
  
  ciop-log "INFO" "Retrieving master"
  master=$( get_data ${master_ref} ${TMPDIR} )
  [ $? -ne 0 ] && return ${ERR_MASTER}
  
  sensing_date=$( get_sensing_date $master )
  [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DAY}
  
  mission=$( get_mission $master | tr "A-Z" "a-z" )
  [ $? -ne 0 ] && return ${ERR_MISSION_MASTER}
  [ ${mission} == "asar" ] && flag="envi"
  # TODO manage ERS and ALOS
  # [ ${mission} == "alos" ] && flag="alos"
  # [ ${mission} == "ers" ] && flag="ers"
  $ [ ${mission} == "ers_envi" ] && flag="ers_envi"
  
  master_folder=${TMPDIR}/SLC/${sensing_date}
  mkdir -p ${master_folder}
  
  get_aux ${sensing_date} ${orbits}
  [ $? -ne 0 ] && return ${ERR_AUX}
  
  cd ${master_folder}
  slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor")"
  ciop-log "INFO" "Run $slc_bin for ${sensing_date}"
  
  ${slc_bin}
  [ $? -ne 0 ] && return ${ERR_SLC}
  
  # package 
  cd ${TMPDIR}/SLC
  tar cfz txt.tgz ar.txt looks.txt
   
  txt_ref="$( echo txt.tgz | ciop-publish -s )" 
  
  tar cfz ${sensing_date}.tgz ${sensing_date}
  master_slc_ref="$( echo ${sensing_date}.tgz | ciop-publish -s )"
  
  while read slave_ref; do
    echo "${master_slc_ref};${txt_ref};${slave_ref}"
  
  done
}

cat | main 
res=$?
[ ${res} -ne 0 ] && exit ${res}
  
[ "$mode" != "test" ] && exit 0
