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
ERR_READ=14
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
    ${ERR_READ}) msg="Error reading the whole TSX";;
  esac
   
  [ "${retval}" != "0" ] && ciop-log "ERROR" \
  "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}

trap cleanExit EXIT

main() {
set -x
  local res
  FIRST="TRUE"
  
  while read scene_ref
  do
 
    [ ${FIRST} == "TRUE" ] && {
      # creates the adore directory structure
      export TMPDIR=$( set_env $_WF_ID )
      export RAW=${TMPDIR}/RAW
      export PROCESS=${TMPDIR}/PROCESS
      export SLC=${PROCESS}/SLC
      export VOR_DIR=${TMPDIR}/VOR
      export INS_DIR=${TMPDIR}/INS

      ciop-log "INFO" "creating the directory structure in $TMPDIR"

      ciop-log "INFO" "Retrieving preliminary master"
      premaster=$( get_data ${scene_ref} ${RAW} ) #for final version
      [ $? -ne 0 ] && return ${ERR_MASTER_EMPTY}

      mission=$( get_mission ${premaster} | tr "A-Z" "a-z" )
      [ $? -ne 0 ] && return ${ERR_MISSION_MASTER}

      # TODO manage ERS and ALOS
      # [ ${mission} == "alos" ] && flag="alos"
      # [ ${mission} == "ers" ] && flag="ers"
      # [ ${mission} == "ers_envi" ] && flag="ers_envi"

      [ ${mission} == "asar" ] && flag="envi"
      [ ${mission} == "tsx" ] && flag="tsx"

      if [[ "$flag" != "tsx" ]];then
 
        # which orbits
        orbits="$( get_orbit_flag )"
        [ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}

        ciop-log "INFO" "Get sensing date"
        sensing_date=$( get_sensing_date ${premaster} )
        [ $? -ne 0 ] && return ${ERR_MASTER_SENSING_DATE}
		
        premaster_folder=${SLC}/${sensing_date}
        mkdir -p ${premaster_folder}

        get_aux "${mission}" "${sensing_date}" ""
        [ $? -ne 0 ] && return ${ERR_AUX}
 
      else	
	
        cd ${RAW}
        tar xvzf ${premaster}
  #      rm -f ${premaster}
        for f in $(find ./ -name "T*.xml"); do
          echo info: $f
    	  bname=$( basename ${f} )
          sensing_date=$(echo $bname | awk -F '_' {'print substr($13,1,8)'} )
        done
        cd ${PROCESS}
        link_slcs ${RAW}

      fi
  
      premaster_folder=${SLC}/${sensing_date}
      cd ${premaster_folder}
      #slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
      #TODO manage the choice of data (IF terrasarX)
      read_bin="step_read_whole_TSX"
      ciop-log "INFO" "Run ${read_bin} for ${sensing_date}"
      ln -s ${premaster}   
      ${read_bin}
      [ $? -ne 0 ] && return ${ERR_READ}
      echo `ls -l ../` 
      #MAS_WIDTH=`grep WIDTH  ${sensing_date}.slc.rsc | awk '{print $2}' `
      #MAS_LENGTH=`grep FILE_LENGTH  ${sensing_date}.slc.rsc | awk '{print $2}' `

      MAS_WIDTH=`grep WIDTH  image.slc.rsc | awk '{print $2}' `
      MAS_LENGTH=`grep FILE_LENGTH  image.slc.rsc | awk '{print $2}' `

      ciop-log "INFO" "Will run step_master_read_geo"
      #echo "first_l 1" > master_crop.in
      #echo "last_l $MAS_LENGTH" >> master_crop.in
      #echo "first_p 1" >> master_crop.in
      #echo "last_p $MAS_WIDTH" >> master_crop.in
     # step_master_setup
      #[ $? -ne 0 ] && return ${ERR_MASTER_SETUP} 
#      step_master_read
 #     [ $? -ne 0 ] && return ${ERR_MASTER_SETUP}
      echo "lon 25.41" > master_crop_geo.in
      echo "lat 36.40" >> master_crop_geo.in
      echo "n_lines 9500" >> master_crop_geo.in
      echo "n_pixels 8850" >> master_crop_geo.in
      cp master_crop_geo.in /tmp/
      cp master_crop_geo.in ../
      step_master_read_geo
      echo `ls -l ../cropfiles.dorisin`
      
      cp ../cropfiles.dorisin ${PROCESS}/INSAR_${sensing_date}
      cp ../readfiles.dorisin ${PROCESS}/INSAR_${sensing_date}
      cd ${PROCESS}
      tar cvfz premaster_${sensing_date}.tgz INSAR_${sensing_date} 
      [ $? -ne 0 ] && return ${ERR_SLC_TAR}

      premaster_slc_ref="$( ciop-publish -a ${PROCESS}/premaster_${sensing_date}.tgz )"
      [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}
    }

    echo "${premaster_slc_ref},${scene_ref}" | ciop-publish -s
    FIRST="FALSE"
  done

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?
