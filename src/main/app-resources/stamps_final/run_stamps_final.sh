#! /bin/bash
mode=$1
#set -x 

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

## source sar helpers and functions
#set_env

MCR="/usr/local/MATLAB/MATLAB_Compiler_Runtime/v717"

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_MASTER_RETRIEVE=7
ERR_STAMPS_5=17
ERR_STAMPS_6=17
ERR_STAMPS_7=17
ERR_STAMPS_8=17
ERR_INSAR_TAR=19
ERR_INSAR_PUBLISH=21
ERR_EXPORT=22
ERR_EXPORT_TAR=23
ERR_EXPORT_PUBLISH=25
ERR_FINAL_PUBLISH=27

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

main() {

  local res

  export TMPDIR=$( set_env )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS

  while read line
  do
    ciop-log "INFO" "Processing input: $line"
    IFS=',' read -r insar_master patches <<< "$line"
    ciop-log "DEBUG" "1:$insar_master 2:$patches"

    if [ ! -d "${PROCESS}/INSAR_${master_date}/" ]
    then
      ciop-log "INFO" "Retrieving Master folder"
      ciop-copy -O ${PROCESS} ${insar_master}
      [ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}    
    
      master_date=`basename ${PROCESS}/I* | cut -c 7-14`   
      ciop-log "INFO" "Final Master Date: $master_date"
    fi
  
    ciop-log "INFO" "Retrieving PATCH folder"
    ciop-copy -O ${PROCESS}/INSAR_${master_date} ${patches}
    # ciop-copy -o ${PROCESS} ${line}
    [ $? -ne 0 ] && return ${ERR_PATCH_RETRIEVE}

    master_date=`basename ${PROCESS}/I* | cut -c 7-14`   
    ciop-log "INFO" "Final Master Date: $master_date"
  done
  
  cd ${PROCESS}/INSAR_${master_date}
  # remove patch list in case exists
  rm -f patch.list
  
  # write new patch list according to stamps parallel if loop (maybe some patches are outsorted by stamps step 4)
  for file in `ls -1 -d PATCH*`
  do  
    echo $file >> patch.list
  done

  ciop-log "INFO" "StaMPS step 5: Phase correction and merge of patches"
  /opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 5 5
  [ $? -ne 0 ] && return ${ERR_STAMPS_5}

  ciop-log "INFO" "StaMPS step 6: PS unwrapping"
  /opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 6 6
  [ $? -ne 0 ] && return ${ERR_STAMPS_6}

  ciop-log "INFO" "StaMPS step 7: Estimation of SCLA and consequent deramping of IFGs"
  /opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 7 7
  [ $? -ne 0 ] && return ${ERR_STAMPS_7}

  ciop-log "INFO" "StaMPS step 8: Spatio-temporal Filtering"
  /opt/StaMPS_v3.3b1/matlab/run_stamps.sh $MCR 8 8
  [ $? -ne 0 ] && return ${ERR_STAMPS_8}

  cd ${PROCESS}
  ciop-log "INFO" "creating tar for InSAR Master folder"
  tar cvfz ${PROCESS}/STAMPS_FILES_${master_date}.tgz  INSAR_${master_date}
  [ $? -ne 0 ] && return ${ERR_INSAR_TAR}

  ciop-log "INFO" "creating tar InSAR Master folder for final export"
  ciop-publish -m ${PROCESS}/STAMPS_FILES_${master_date}.tgz
  [ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}
  
  # EXPORT PART --------------------------------------------------------------------------------
  #cd ${PROCESS}/INSAR_${master_date}
  #ciop-log "INFO" "StaMPS export for GIS layers"
  #/opt/StaMPS_v3.3b1/matlab/export_L0_V_DOS $MCR
  #[ $? -ne 0 ] && return ${ERR_EXPORT}
  
  # Stamps Mode of Velocity
  #SUF_VEL=V-DOS
  # Stamps Mode of Std.dev.
  #SUF_STD=VS-DO

  # export folder wth csv
  #SOURCE=${PROCESS}/INSAR_${master_date}/export

  # output folder for GIS layers
  #GIS_RESULTS=$PROCESS/INSAR_${master_date}/GIS-RESULTS
  #mkdir -p $GIS_RESULTS

  # Output Resolution in degree
  #RESOL=0.001

  # write shapefile/tif in result folder script
  #ogr2ogr -overwrite -f "ESRI Shapefile" $GIS_RESULTS/$SUF_VEL.shp $SOURCE/$SUF_VEL.vrt
  #gdal_rasterize -a VEL -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/$SUF_VEL.tif
  #gdal_rasterize -a V_STDEV -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/$SUF_STD.tif
  #gdal_rasterize -a COH -tr $RESOL $RESOL -l $SUF_VEL $GIS_RESULTS/$SUF_VEL.shp $GIS_RESULTS/Coherence.tif

  #ciop-log "INFO" "creating tar for GIS result layers"
  #tar cvfz GIS_${master_date}.tgz  GIS-RESULTS
  #[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

  #ciop-log "INFO" "publishing GIS result layers"
  #ciop-publish ${PROCESS}/GIS_${master_date}.tgz
  #[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}
  # EXPORT PART --------------------------------------------------------------------------------

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}

  return ${SUCCESS}
}

cat | main
exit $?
