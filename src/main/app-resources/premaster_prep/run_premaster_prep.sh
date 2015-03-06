#!/bin/bash
mode=$1


export PATH=${_CIOP_APPLICATION_PATH}/master_slc/bin:$PATH


# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# define the exit codes
SUCCESS=0
ERR_ORBIT_FLAG=5
ERR_MASTER_EMPTY=7
ERR_MASTER_SENSING_DATE=9
ERR_MISSION_MASTER=11 
ERR_AUX=13
ERR_SLC=15 
ERR_MASTER_SETUP=16
ERR_SLC_AUX_TAR=17
ERR_SLC_AUX_PUBLISH=19
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23


# add a trap to exit gracefully
function cleanExit() {
  local retval=$?
  local msg

  msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit files to use";;
    ${ERR_MASTER_EMPTY}) msg="Couldn't retrieve master";;
    ${ERR_MASTER_SENSING_DATE}) msg="Couldn't retrieve master sensing date";;
    ${ERR_MISSION_MASTER}) msg="Couldn't determine master mission";;
    ${ERR_AUX}) msg="Couldn't retrieve auxiliary files";;
    ${ERR_SLC}) msg="Failed to process slc";;
    ${ERR_SLC_AUX_TAR}) msg="Failed to create archive with master ROI_PAC aux files";;
    ${ERR_SLC_AUX_PUBLISH}) msg="Failed to publish archive with master ROI_PAC aux files";;
    ${ERR_SLC_TAR}) msg="Failed to create archive with master slc";;
    ${ERR_SLC_PUBLISH}) msg="Failed to publish archive with master slc";;
  esac
   
  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
 # [ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
   [ -n "${TMPDIR}" ] && chmod -R 777 $TMPDIR
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
  
  premaster_ref="$( ciop-getparam master )"
  [ $? -ne 0 ] && return ${ERR_MASTER_REF}

   ciop-log "INFO" "Retrieving master"
#  master=$( get_data ${master_ref} ${TMPDIR} ) #for final version
   premaster=`echo ${premaster_ref} | ciop-copy -o ${RAW} -f -`
   [ $? -ne 0 ] && return ${ERR_MASTER_EMPTY}
  
  ciop-log "INFO" "Get sensing date"
  sensing_date=$( get_sensing_date ${premaster} )
  [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DATE}
  
  mission=$( get_mission ${premaster} | tr "A-Z" "a-z" )
  [ $? -ne 0 ] && return ${ERR_MISSION_MASTER}
  [ ${mission} == "asar" ] && flag="envi"
  
  # TODO manage ERS and ALOS
  # [ ${mission} == "alos" ] && flag="alos"
  # [ ${mission} == "ers" ] && flag="ers"
  # [ ${mission} == "ers_envi" ] && flag="ers_envi"
  
  premaster_folder=${SLC}/${sensing_date}
  mkdir -p ${premaster_folder}
  
  get_aux ${mission} ${sensing_date} ${orbits} 
  [ $? -ne 0 ] && return ${ERR_AUX}
  
  cd ${premaster_folder}
  slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
  ciop-log "INFO" "Run ${slc_bin} for ${sensing_date}"
  ln -s ${premaster}   
  ${slc_bin}
  [ $? -ne 0 ] && return ${ERR_SLC}
 
  # TODO check with expert what are ALL the processing steps for the master
  

  MAS_WIDTH=`grep WIDTH  ${sensing_date}.slc.rsc | awk '{print $2}' `
  MAS_LENGTH=`grep FILE_LENGTH  ${sensing_date}.slc.rsc | awk '{print $2}' `

  ciop-log "INFO" "Will run step_master_setup"
  echo "first_l 1" > master_crop.in
  echo "last_l $MAS_LENGTH" >> master_crop.in
  echo "first_p 1" >> master_crop.in
  echo "last_p $MAS_WIDTH" >> master_crop.in
  step_master_setup
  [ $? -ne 0 ] && return ${ERR_MASTER_SETUP} 

  # package 
 # cd ${SLC}
 # tar cvfz txt.tgz ar.txt looks.txt
 # [ $? -ne 0 ] && return ${ERR_SLC_AUX_TAR}
   
  #txt_ref="$( ciop-publish -a ${TMPDIR}/SLC/txt.tgz )" 
  #[ $? -ne 0 ] && return ${ERR_SLC_AUX_PUBLISH}
  #rm -f txt.tgz 
 
  cd ${PROCESS}
  tar cvfz premaster_${sensing_date}.tgz INSAR_${sensing_date} 
#${sensing_date}.tgz ${sensing_date}
  [ $? -ne 0 ] && return ${ERR_SLC_TAR}
  premaster_slc_ref="$( ciop-publish -a ${PROCESS}/premaster_${sensing_date}.tgz )"
  [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}
  
  while read scene_ref; do
    #echo "${premaster_slc_ref},${txt_ref},${scene_ref}" | ciop-publish -s
    echo "${premaster_slc_ref},${scene_ref}" | ciop-publish -s
  done

chmod -R 777 $TMPDIR # not for final version
}
cat | main
res=$?
exit ${res}
