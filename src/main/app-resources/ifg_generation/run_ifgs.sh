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

#--------------------------------
#       2) Error Handling       
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_MASTER_RETRIEVE=7
ERR_DEM_RETRIEVE=9
ERR_SLC_RETRIEVE=11
ERR_STEP_COARSE=13
ERR_STEP_COREG=15
ERR_STEP_DEM=17
ERR_STEP_RESAMPLE=19
ERR_STEP_IFG=21
ERR_INSAR_SLAVES_TAR=23
ERR_INSAR_SLAVES_PUBLISH=25
ERR_FINAL_PUBLISH=27

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

main() {
  local res
  master_date=""

  export TMPDIR=$( set_env )
  export RAW=${TMPDIR}/RAW
  export PROCESS=${TMPDIR}/PROCESS
  export SLC=${PROCESS}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS

  while read line
  do

    ciop-log "INFO" "Processing input: $line"

    insar_master=`echo "$line" | cut -d "," -f 1`
    slc_folders=`echo "$line" | cut -d "," -f 2`
    dem=`echo "$line" | cut -d "," -f 3`

    ciop-log "DEBUG" "1:$insar_master 2:$slc_folders 3:$dem"

    if [ ! -d "${PROCESS}/INSAR_${master_date}" ]
    then
      ciop-log "INFO" "Retrieving Master folder"
      ciop-copy -O ${PROCESS} ${insar_master}
      [ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
      fix_res_path "${PROCESS}"

      master_date=`basename ${PROCESS}/I* | cut -c 7-14`   
      ciop-log "INFO" "Final Master Date: $master_date"
    fi

    if [ ! -e "${TMPDIR}/DEM/final_dem.dem" ]
    then
      ciop-log "INFO" "Retrieving DEM folder"
      ciop-copy -O ${TMPDIR} ${dem}
      [ $? -ne 0 ] && return ${ERR_DEM_RETRIEVE}
    fi

    ciop-log "INFO" "Retrieving SLC folder"
    ciop-copy -O ${SLC} ${slc_folders}
    [ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}
    fix_res_path "${SLC}"

    # get sensing date
    sensing_date=`basename ${slc_folders} | cut -c 1-8`
    ciop-log "INFO" "Processing scene from $sensing_date"
  
    # Process all slaves
    if [ $sensing_date != $master_date ]
    then
      # go to master folder
      cd ${PROCESS}/INSAR_${master_date}

      ## adjust the original file paths for the current node         
      #sed -i "61s|Data_output_file:.*|Data_output_file:\t${PROCESS}/INSAR_${master_date}/${master_date}\_crop.slc|" master.res
      #sed -i "s|DEM source file:.*|DEM source file:\t  ${TMPDIR}/DEM/final_dem.dem|" master.res     
      #sed -i "s|MASTER RESULTFILE:.*|MASTER RESULTFILE:\t${PROCESS}/INSAR_${master_date}/master.res|" master.res
    
      # create slave folder and change to it
      rm -rf ${sensing_date}  # in case of same master as premaster
      mkdir -p ${sensing_date}
      cd ${sensing_date}
   
      # link to SLC folder
      rm -rf SLC
      ln -s ${SLC}/${sensing_date} SLC

      # get the master and slave doris result files
      cp -f SLC/slave.res  .
      cp -f ../master.res .

      #   adjust paths for current node    
      sed -i "s|Data_output_file:.*|Data_output_file:  $SLC/${sensing_date}/${sensing_date}.slc|" slave.res
      sed -i "s|SLAVE RESULTFILE:.*|SLAVE RESULTFILE:\t$SLC/${sensing_date}/slave.res|" slave.res              

      # copy Stamps version of coarse.dorisin into slave folder
      cp $DORIS_SCR/coarse.dorisin .
      rm -f coreg.out
  
      # change number of corr. windows to 500 for more robust processsing (especially for scenes with water)
      sed -i 's/CC_NWIN.*/CC_NWIN         500/' coarse.dorisin  
    
      ciop-log "INFO" "coarse image correlation for ${sensing_date}"
      doris coarse.dorisin > step_coarse.log
      [ $? -ne 0 ] && return ${ERR_STEP_COARSE}
  
      # get all calculated coarse offsets (line 85 - 584) and take out the value which appears most for better calculation of overall offset
      offsetL=`cat coreg.out | sed -n -e 85,584p | awk $'{print $5}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`
      offsetP=`cat coreg.out | sed -n -e 85,584p | awk $'{print $6}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`

      # write the lines with the new overall offset into variable   
      replaceL=`echo -e "Coarse_correlation_translation_lines: \t" $offsetL`
      replaceP=`echo -e "Coarse_correlation_translation_pixels: \t" $offsetP`  

      # replace full line of overall offset
      sed -i "s/Coarse_correlation_translation_lines:.*/$replaceL/" coreg.out
      sed -i "s/Coarse_correlation_translation_pixels:.*/$replaceP/" coreg.out
    
      ciop-log "INFO" "fine image correlation for ${sensing_date}"
      step_coreg_simple
      [ $? -ne 0 ] && return ${ERR_STEP_COREG}

      # only process images with enough GCPs in CPM_data file
      if [ `ls -s CPM_Data | awk $'{print $1}'` -gt 4 ]
      then
        # prepare dem.dorisin with right dem path if does not exist 
        if [ ! -e ${PROCESS}/INSAR_${master_date}/dem.dorisin ]
        then
          sed -n '1,/step comprefdem/p' $DORIS_SCR/dem.dorisin > ${PROCESS}/INSAR_${master_date}/dem.dorisin
          echo "# CRD_METHOD      trilinear" >> ${PROCESS}/INSAR_${master_date}/dem.dorisin
          echo "CRD_INCLUDE_FE  OFF" >> ${PROCESS}/INSAR_${master_date}/dem.dorisin
          echo "CRD_OUT_FILE    refdem_1l.raw" >> ${PROCESS}/INSAR_${master_date}/dem.dorisin
          echo "CRD_OUT_DEM_LP  dem_radar.raw" >> ${PROCESS}/INSAR_${master_date}/dem.dorisin
          grep "SAM_IN" ${PROCESS}/INSAR_${master_date}/timing.dorisin | sed 's/SAM/CRD/' >> ${PROCESS}/INSAR_${master_date}/dem.dorisin      
          echo "STOP" >> ${PROCESS}/INSAR_${master_date}/dem.dorisin
  
          sed -i "s|CRD_IN_DEM.*|CRD_IN_DEM ${TMPDIR}/DEM/final_dem.dem|" ${PROCESS}/INSAR_${master_date}/dem.dorisin
          sed -i "s|SAM_IN_DEM.*|SAM_IN_DEM ${TMPDIR}/DEM/final_dem.dem|" ${PROCESS}/INSAR_${master_date}/timing.dorisin
        fi

        ciop-log "INFO" "simulating amplitude for ${sensing_date}"
        step_dem
        [ $? -ne 0 ] && return ${ERR_STEP_DEM}
   
        ciop-log "INFO" "resampling ${sensing_date}"
        step_resample
        [ $? -ne 0 ] && return ${ERR_STEP_RESAMPLE}

        ciop-log "INFO" "IFG generation for ${sensing_date}"
        step_ifg
        [ $? -ne 0 ] && return ${ERR_STEP_IFG}

        cd ${PROCESS}/INSAR_${master_date}
        ciop-log "INFO" "create tar for INSAR SLave folder"
        tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}/slave_res.slc ${sensing_date}/cint.minrefdem.raw ${sensing_date}/dem_radar.raw ${sensing_date}/*.out ${sensing_date}/*.res ${sensing_date}/*.log ${sensing_date}/*.dorisin
        [ $? -ne 0 ] && return ${ERR_INSAR_SLAVES_TAR}  #${sensing_date}/ref_dem1l.raw 

        ciop-log "INFO" "Publish -a insar_slaves"
        insar_slaves="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}/INSAR_${sensing_date}.tgz )"
        [ $? -ne 0 ] && return ${ERR_INSAR_SLAVES_PUBLISH}
    
        ciop-log "INFO" "Will publish the final output"
        echo "${insar_master},${insar_slaves},${dem}" | ciop-publish -s  
        [ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}
 
        echo "${insar_master},${insar_slaves},${dem}" >> $TMPDIR/output.list
    
      fi 
    fi
  done

  ciop-log "INFO" "removing temporary files $TMPDIR"
  rm -rf ${TMPDIR}
}

cat | main
exit $?
