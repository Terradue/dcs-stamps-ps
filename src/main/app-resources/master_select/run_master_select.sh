#! /bin/bash
mode=$1

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

## source sar helpers and functions
#set_env

DEM_ROUTINES="${_CIOP_APPLICATION_PATH}/master_select/bin"
PATH=$DEM_ROUTINES:$PATH

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_PREMASTER=5
ERR_INSAR_SLAVES=7
ERR_MASTER_SELECT=9
ERR_MASTER_COPY=11
ERR_MASTER_SLC=12
ERR_MASTER_SETUP=13
ERR_DEM=14
ERR_MASTER_TIMING=21
ERR_INSAR_TAR=15
ERR_INSAR_PUBLISH=17
ERR_FINAL_PUBLISH=19
ERR_DEM_TAR=21
ERR_DEM_PUBLISH=23

# add a trap to exit gracefully
cleanExit() {
  local retval=$?
  local msg
  msg=""

  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_PREMASTER}) msg="couldn't retrieve ";; 
    ${ERR_INSAR_SLAVES}) msg="couldn't retrieve insar slave folders";;
    ${ERR_INSAR_SLAVES_TAR}) msg="couldn't extract insar slave folders";;
    ${ERR_MASTER_SELECT}) msg="couldn't calculate most suited master image";;
    ${ERR_MASTER_COPY}) msg="couldn't retrieve final master";;
    ${ERR_MASTER_SLC_TAR}) msg="couldn't untar final master SLC";;
    ${ERR_MASTER_SETUP}) msg="couldn't setup new INSAR_MASTER folder";;
    ${ERR_DEM}) msg="could not create DEM";;
    ${ERR_MASTER_TIMING}) msg="couldn't run step_master_timing";;
    ${ERR_INSAR_TAR}) msg="couldn't create tgz archive for publishing";;
    ${ERR_INSAR_PUBLISH}) msg="couldn't publish new INSAR_MASTER folder";;
    ${ERR_DEM_TAR}) msg="couldn't create DEM.tgz archive for publishing";;
    ${ERR_DEM_PUBLISH}) msg="couldn't publish the DEM folder";;
    ${ERR_FINAL_PUBLISH}) msg="couldn't publish final output";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" \
    "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  [ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

dem() {
  local dataset_ref=$1
  local target=$2
  local bbox
  local wkt
 
  #wkt="$( ciop-casmeta -f "dct:spatial" "${dataset_ref}" )"
  wkt="$( opensearch-client "${dataset_ref}" wkt | head -1 )"
  [ -n "${wkt}" ] && bbox="$( mbr.py "${wkt}" )" || return 1

  wdir=${PWD}/.wdir
  mkdir ${wdir}
  mkdir -p ${target}

  target=$( cd ${target} && pwd )

  cd ${wdir}
  construct_dem.sh dem ${bbox} SRTM3 || return 1
  
  cp -v ${wdir}/dem/final_dem.dem ${target}
  cp -v ${wdir}/dem/input.doris_dem ${target}

  sed -i "s#\(SAM_IN_DEM *\).*/\(final_dem.dem\)#\1$target/\2#g" ${target}/input.doris_dem
  cd - &> /dev/null

  rm -fr ${wdir}
  return 0
}

main() {

  local res
  premaster_date=""

  export TMPDIR=$( set_env )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS

  # copy INSAR_PREMASTER from input
  while read line
  do
    ciop-log "INFO" "Processing input: ${line}"
    IFS=',' read -r premaster_slc_ref slc_folders insar_slaves <<< "${line}"
    ciop-log "DEBUG" "1:${premaster_slc_ref} 2:${slc_folders} 3:${insar_slaves}"
  
    if [ ! -d ${PROCESS}/INSAR_${premaster_date} ]
    then
      ciop-copy -O ${PROCESS} ${premaster_slc_ref}
      [ $? -ne 0 ] && return ${ERR_PREMASTER}
      fix_res_path "${PROCESS}"

      premaster_date=`basename ${PROCESS}/I* | cut -c 7-14`   
      ciop-log "INFO" "Pre-Master Date: ${premaster_date}"
    fi

    ciop-log "INFO" "Retrieve folder: ${insar_slaves}"
    ciop-copy -f -O ${PROCESS}/INSAR_${premaster_date}/ ${insar_slaves}
    [ $? -ne 0 ] && return ${ERR_INSAR_SLAVES}  
    fix_res_path "${PROCESS}/INSAR_${premaster_date}"
  
    echo ${slc_folders} >> ${TMPDIR}/slc_folders.tmp  
  done

  cd $PROCESS/INSAR_${premaster_date}

  master_select > master.date
  [ $? -ne 0 ] && return ${ERR_MASTER_SELECT}
  master_date=`awk 'NR == 12' master.date | awk $'{print $1}'`

  ciop-log "INFO" "Choose SLC from ${master_date} as final master"
  master=`grep ${master_date} ${TMPDIR}/slc_folders.tmp`

  ciop-log "INFO" "Retrieve final master SLC from ${master_date}"
  ciop-copy -f -O ${SLC}/ ${master}
  fix_res_path "${SLC}"

  cd ${SLC}/${master_date}

  # get extents
  MAS_WIDTH=`grep WIDTH ${master_date}.slc.rsc | awk '{print $2}' `
  MAS_LENGTH=`grep FILE_LENGTH ${master_date}.slc.rsc | awk '{print $2}' `

  ciop-log "INFO" "Running step_master_setup"
  echo "first_l 1" > master_crop.in
  echo "last_l ${MAS_LENGTH}" >> master_crop.in
  echo "first_p 1" >> master_crop.in
  echo "last_p ${MAS_WIDTH}" >> master_crop.in

#  echo "first_l 10000" > master_crop.in
#  echo "last_l 13000" >> master_crop.in
#  echo "first_p 2000" >> master_crop.in
#  echo "last_p 4000" >> master_crop.in

  step_master_setup
  [ $? -ne 0 ] && return ${ERR_MASTER_SETUP} 

  # DEM steps
  # getting the original file url for dem fucntion
  master_ref=`cat $master_date.url`
  ciop-log "INFO" "Prepare DEM with: $master_ref"    
  dem ${master_ref} ${TMPDIR}/DEM
  [ $? -ne 0 ] && return ${ERR_DEM}

  head -n 28 ${STAMPS}/DORIS_SCR/timing.dorisin > ${PROCESS}/INSAR_${master_date}/timing.dorisin
  cat ${TMPDIR}/DEM/input.doris_dem >> ${PROCESS}/INSAR_${master_date}/timing.dorisin  
  tail -n 13 ${STAMPS}/DORIS_SCR/timing.dorisin >> ${PROCESS}/INSAR_${master_date}/timing.dorisin  

  cd ${PROCESS}/INSAR_${master_date}/
  ciop-log "INFO" "Running step_master_timing"    
  step_master_timing
  [ $? -ne 0 ] && return ${ERR_MASTER_TIMING}

  ciop-log "INFO" "Archiving the newly created INSAR_$master_date folder"
  cd ${PROCESS}
  tar cvfz INSAR_${master_date}.tgz INSAR_${master_date}
  [ $? -ne 0 ] && return ${ERR_INSAR_TAR}

  ciop-log "INFO" "Publishing the newly created INSAR_${master_date} folder"
  insar_master=$( ciop-publish -a ${PROCESS}/INSAR_${master_date}.tgz )
  [ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}

  cd ${TMPDIR}
  ciop-log "INFO" "Archiving the DEM folder"
  tar cvfz DEM.tgz DEM
  [ $? -ne 0 ] && return ${ERR_DEM_TAR}

  ciop-log "INFO" "Publishing the DEM folder"
  dem=$( ciop-publish -a ${TMPDIR}/DEM.tgz )
  [ $? -ne 0 ] && return ${ERR_DEM_PUBLISH}
  
  for slcs in `cat ${TMPDIR}/slc_folders.tmp`
  do
    ciop-log "INFO" "Will publish the final output"
    echo "${insar_master},${slcs},${dem}" | ciop-publish -s  
    [ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}

    echo "${insar_master},${slcs},${dem}" >> ${TMPDIR}/output.list
  done

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?

