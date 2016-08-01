#! /bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# source sar helpers and functions
#set_env

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_SCENE=3
ERR_ORBIT_FLAG=5
ERR_SENSING_DATE=9
ERR_MISSION=11
ERR_AUX=13
ERR_LINK_RAW=15
ERR_SLC=17
ERR_SLC_TAR=21
ERR_SLC_PUBLISH=23
ERR_MASTER=29
ERR_MASTER_REF=31
ERR_SENSING_DATE_MASTER=33
ERR_STEP_ORBIT=25
ERR_STEP_COARSE=27
ERR_INSAR_TAR=35
ERR_INSAR_PUBLISH=37

# add a trap to exit gracefully
cleanExit() {
  local retval=$?
  local msg
  msg=""
  
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_SCENE}) msg="Failed to retrieve scene";;
    ${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit file format to use";;
    ${ERR_SENSING_DATE}) msg="Couldn't retrieve scene sensing date";;
    ${ERR_MISSION}) msg="Couldn't determine the satellite mission for the scene";;
    ${ERR_AUX}) msg="Couldn't retrieve auxiliary files";;
    ${ERR_LINK_RAW}) msg="Failed to link the raw data to SLC folder";;
    ${ERR_SLC}) msg="Failed to focalize raw data with ROI-PAC";;
    ${ERR_SLC_TAR}) msg="Failed to create archive with scene";;
    ${ERR_SLC_PUBLISH}) msg="Failed to publish archive with slc";;
    ${ERR_MASTER}) msg="Failed to retrieve master";;
    ${ERR_MASTER_REF}) msg="Failed to get the reference master";;
    ${ERR_SENSING_DATE_MASTER}) msg"Failed ot get Master DAte";;
    ${ERR_STEP_ORBIT}) msg="Failed to process step_orbit";;
    ${ERR_STEP_COARSE}) msg="Failed to process step_coarse";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

#--------------------------------
#       3) Main Function        
#--------------------------------
main() {

  local res

  first=TRUE
  premaster_date=""

  export TMPDIR=$( set_env )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS  

  ciop-log "INFO" "creating the directory structure in $TMPDIR"

  # download data into $RAW
  while read line
  do
    mkdir -p ${RAW}
    ciop-log "INFO" "Processing input: ${line}"
    IFS=',' read -r premaster_slc_ref scene_ref <<< "${line}"

    ciop-log "DEBUG" "1:${premaster_slc_ref} 2:${scene_ref}"

    #if it's the first scene we have to download and setup the master as well
    [ "${first}" == "TRUE" ] && {
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      fix_res_path "${PROCESS}"
      first="FALSE"
    }

    scene=$( get_data ${scene_ref} ${RAW} ) 
    #scene=$( ciop-copy -f -O ${RAW} $( echo ${scene_ref} | tr -d "\t")  )
    [ $? -ne 0 ] && return ${ERR_SCENE}
    fix_res_path "$RAW"
    ciop-log "INFO" "Processing scene: ${scene}"

    # which orbits (defined in application.xml)
    #orbits="$( get_orbit_flag )"
    #[ $? -ne 0 ] && return ${ERR_ORBIT_FLAG}
    #ciop-log "INFO" "Orbit format used: ${orbits}" 

    ciop-log "INFO" "Get sensing date"
    #sensing_date=$( get_sensing_date ${scene} )
    #[ $? -ne 0 ] && return ${ERR_SENSING_DATE}

    ciop-log "INFO" "Get Sensor"
    mission=$( get_mission ${scene} | tr "A-Z" "a-z" )
    [ $? -ne 0 ] && return ${ERR_MISSION}
    [ ${mission} == "asar" ] && flag="envi"
    ciop-log "INFO" "Sensor: ${mission}"   

    ciop-log "INFO" "Get Auxilary data"
    #get_aux ${mission} ${sensing_date} ${orbits}
    [ $? -ne 0 ] && return ${ERR_AUX}

    # link_raw
    #ciop-log "INFO" "Set-up Stamps Structure (i.e. run step link_raw)"
    #link_raw ${RAW} ${PROCESS}
    #[ $? -ne 0 ] && return ${ERR_LINK_RAW}
    cd ${RAW}
    tar xvzf ${scene}
    #rm -rf ${scene}

    for f in $(find ./ -name "T*.xml"); do
        echo info: $f
        bname=$( basename ${f} )
        sensing_date=$(echo $bname | awk -F '_' {'print substr($13,1,8)'} )
    done
    ciop-log "INFO" "Sensing date: ${sensing_date}"

    ciop-log "INFO" "Running link_slcs"
    cd ${PROCESS}
    link_slcs ${RAW}

    ciop-log "INFO" "Preparing step_read_geo"   
    scene_folder=${SLC}/${sensing_date}
    cd ${scene_folder}
    cp -f $DORIS_SCR/readfiles_TSX.dorisin ../readfiles.dorisin
    cp -f $DORIS_SCR/cropfiles_TSX.dorisin ../cropfiles.dorisin    
    #slc_bin="step_slc_${flag}$( [ ${orbits} == "VOR" ] && [ ${mission} == "asar" ] && echo "_vor" )"
    slc_bin="step_read_geo"
    ciop-log "INFO" "Run ${slc_bin} for ${sensing_date}"
    ${slc_bin}
    [ $? -ne 0 ] && return ${ERR_SLC}

    # writing original image url for node master_select (need for newly master)
    echo ${scene_ref} > ${sensing_date}.url  

    # publish for next node
    cd ${SLC}
    ciop-log "INFO" "create tar"
    tar cvfz ${sensing_date}.tgz ${sensing_date}
    [ $? -ne 0 ] && return ${ERR_SLC_TAR}

    ciop-log "INFO" "Publishing -a"
    slc_folders="$( ciop-publish -a ${SLC}/${sensing_date}.tgz )"
    [ $? -ne 0 ] && return ${ERR_SLC_PUBLISH}

    premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`
    [ ! -d "${PROCESS}/INSAR_${premaster_date}" ] && ciop-log "DEBUG" "${PROCESS}/INSAR_${premaster_date} does not exist" || ciop-log "DEBUG" "${PROCESS}/INSAR_${premaster_date} exists"
    if [ ! -d "${PROCESS}/INSAR_${premaster_date}" ]
    then
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      [ $? -ne 0 ] && return ${ERR_MASTER}
      fix_res_path "${PROCESS}"

      premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`
      [ $? -ne 0 ] && return ${ERR_SENSING_DATE_MASTER}
      ciop-log "INFO" "Pre-Master Date: ${premaster_date}"
    fi

    ciop-log "INFO" "Sensing date before if: $sensing_date"
  
    if [ "${sensing_date}" != "${premaster_date}" ]
    then
      cd ${PROCESS}/INSAR_${premaster_date}
      mkdir ${sensing_date}
      cd ${sensing_date}

      # step_orbit (extract orbits)
    #  ln -s ${SLC}/${sensing_date} SLC
    #  ciop-log "INFO" "step_orbit for ${sensing_date} "
    #  step_orbit
    #  [ $? -ne 0 ] && return ${ERR_STEP_ORBIT}
  
      ciop-log "INFO" "doing image coarse correlation for ${sensing_date}"
      step_coarse
      [ $? -ne 0 ] && return ${ERR_STEP_COARSE}

      cd ../

      ciop-log "INFO" "create tar"
      tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}
      [ $? -ne 0 ] && return ${ERR_INSAR_TAR}

      ciop-log "INFO" "Publish -a insar_slaves"
      insar_slaves="$( ciop-publish -a ${PROCESS}/INSAR_${premaster_date}/INSAR_${sensing_date}.tgz )"
    else
      insar_slaves=""
    fi 

    ciop-log "INFO" "Publish -s"
    echo "${premaster_slc_ref},${slc_folders},${insar_slaves}" | ciop-publish -s

    rm -rf ${RAW}
    cd -
  done

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?

