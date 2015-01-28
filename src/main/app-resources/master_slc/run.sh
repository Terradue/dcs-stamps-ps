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
  local orbit_flag
  orbit_flag="$( ciop-getparam orbit )"
  [ ${orbit_flag} != "VOR" ] && [ ${orbit_flag} != "ODR" ] && return 1
  echo ${orbit_flag}
  return 0
}

get_aux() {
  local mission=$1
  local sensing_date=$2
  local orbit_flag=$3
  
  [ ${orbit_flag} == "VOR" ] && {
    local aux_cat="http://catalogue.terradue.int/catalogue/search/rdf"
    start="$( date -d "${sensing_date} 3 days ago" +%Y-%m-%dT00:00:00 )"
    stop="$( date -d "${sensing_date} 3 days" +%Y-%m-%dT00:00:00 )"
    
    mkdir -p ${TMPDIR}/VOR
  
    opensearch-client -p "time:start=${start}" \
      -p "time:end=${stop}" \
      "${aux_cat}" enclosure |
      while read url; do
        echo ${url} | ciop-copy -O ${TMPDIR}/VOR
      done
  } 
  
  [ ${orbit_flag} == "ODR" ] &&
    # TODO add ASAR_ODR.tgz, ERS1, ERS2 to /application/aux
    tar -C ${TMPDIR} ${_CIOP_APPLICATION_PATH}/aux/${mission}_ODR.tgz
    
  }
  
  
}

main() {
  local res

  # creates the adore directory structure
  ciop-log "INFO" "creating the directory structure"
  set_env
  
  # which orbits
  orbits="$( get_orbit_flag )"
  [ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}
  
  master_ref="$( ciop-getparam master )"
  
  ciop-log "INFO" "Retrieving master"
  master=$( get_data ${master_ref} ${TMPDIR} )
  [ $? -ne 0 ] && return ${ERR_MASTER_EMPTY}
  
  sensing_date=$( get_sensing_date $master )
  [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DATE}
  
  mission=$( get_mission ${master} | tr "A-Z" "a-z" )
  [ $? -ne 0 ] && return ${ERR_MISSION_MASTER}
  [ ${mission} == "asar" ] && flag="envi"
  
  # TODO manage ERS and ALOS
  # [ ${mission} == "alos" ] && flag="alos"
  # [ ${mission} == "ers" ] && flag="ers"
  $ [ ${mission} == "ers_envi" ] && flag="ers_envi"
  
  master_folder=${TMPDIR}/SLC/${sensing_date}
  mkdir -p ${master_folder}
  
  get_aux ${mission} ${sensing_date} ${orbits} 
  [ $? -ne 0 ] && return ${ERR_AUX}
  
  cd ${master_folder}
  slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor")"
  ciop-log "INFO" "Run $slc_bin for ${sensing_date}"
  
  ${slc_bin}
  [ $? -ne 0 ] && return ${ERR_SLC}
  
  # package 
  cd ${TMPDIR}/SLC
  tar cvfz txt.tgz ar.txt looks.txt
   
  txt_ref="$( ciop-publish txt.tgz )" 
  
  tar cvfz ${sensing_date}.tgz ${sensing_date}
  master_slc_ref="$( ciop-publish ${sensing_date}.tgz )"
  
  while read slave_ref; do
    echo "${master_slc_ref} ${txt_ref} ${slave_ref}" | ciop-publish -s
  done
}

cat | main 
res=$?
[ ${res} -ne 0 ] && exit ${res}
  
[ "$mode" != "test" ] && exit 0
