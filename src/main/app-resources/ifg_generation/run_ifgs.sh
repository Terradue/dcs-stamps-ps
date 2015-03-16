#! /bin/bash
mode=$1
#set -x 

# source the ciop functions (e.g. ciop-log)
[ "${mode}" != "test" ] && source ${ciop_job_include}

# source extra functions
source ${_CIOP_APPLICATION_PATH}/lib/stamps-helpers.sh

# source StaMPS
source /opt/StaMPS_v3.3b1/StaMPS_CONFIG.bash

# source sar helpers and functions
set_env

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
${ERR_MASTER_RETRIEVE}) msg="Failed to retrieve Master folder";;
${ERR_DEM_RETRIEVE}) msg="Failed to retrieve DEM folder";;
${ERR_SLC_RETRIEVE) msg="Failed to retrieve SLC folder";;
${ERR_STEP_COARSE}) msg="Failed to do coarse image correlation";;
${ERR_STEP_COREG}) msg="Failed to do fine image correlation";;
${ERR_STEP_DEM}) msg="Failed to do simulate amplitude";;
${ERR_STEP_RESAMPLE) msg="Failed to resample image";;
${ERR_STEP_IFG}) msg=" Failed to create IFG";;
${ERR_INSAR_SLAVES_TAR}) msg="Failed to tar Insar Slave folder";;
${ERR_INSAR_SLAVES_PUBLISH}) msg="Failed to publish Insar Slave folder";;
${ERR_FINAL_PUBLISH}) msg="Failed to publish all output together";;
esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
#[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ -n "${TMPDIR}" ] && chmod -R 777 $TMPDIR
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

main() {
local res
master_date=""

while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master slc_folders dem <<< "$line"
	ciop-log "DEBUG" "1:$insar_master 2:$slc_folders 3:$dem"

	if [ ! -d "${PROCESS}/INSAR_${master_date}/" ]; then
	
		ciop-log "INFO" "Retrieving Master folder"
		ciop-copy -O ${PROCESS} ${insar_master}
		[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
		master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Final Master Date: $master_date"
		
	fi

	if [ ! -e "${TMPDIR}/DEM/final_dem.dem" ]; then

	ciop-log "INFO" "Retrieving DEM folder"
	ciop-copy -O ${TMPDIR} ${dem}
	[ $? -ne 0 ] && return ${ERR_DEM_RETRIEVE}

	fi

	ciop-log "INFO" "Retrieving SLC folder"
	ciop-copy -O ${SLC} ${slc_folders}
	[ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}
	
	# 	get sensing date
	sensing_date=`basename ${slc_folders} | cut -c 1-8`
	ciop-log "INFO" "Processing scene from $sensing_date"
	
	# 	Process all slaves
	if [ $sensing_date != $master_date ];then
		
		# 	go to master folder
		cd ${PROCESS}/INSAR_${master_date}

		# 	adjust the original file paths for the current node	       
		sed -i "61s|Data_output_file:.*|Data_output_file:\t${PROCESS}/INSAR_${master_date}/${master_date}\_crop.slc|" master.res
		sed -i "s|DEM source file:.*|DEM source file:\t	${TMPDIR}/DEM/final_dem.dem|" master.res     
		sed -i "s|MASTER RESULTFILE:.*|MASTER RESULTFILE:\t${PROCESS}/INSAR_${master_date}/master.res|" master.res
		
		# 	create slave folder and change to it
		mkdir ${sensing_date}
		cd ${sensing_date}
		
		# 	link to SLC folder
		ln -s ${SLC}/${sensing_date} SLC

		# 	get the master and slave doris result files
		cp -f SLC/slave.res  .
		cp -f ../master.res .

		# 	adjust paths for current node		
		sed -i "s|Data_output_file:.*|Data_output_file:  $SLC/${sensing_date}/$sensing_date.slc|" slave.res
		sed -i "s|SLAVE RESULTFILE:.*|SLAVE RESULTFILE:\t$SLC/${sensing_date}/slave.res|" slave.res            	

		# 	copy Stamps version of coarse.dorisin into slave folder
		cp $DORIS_SCR/coarse.dorisin .
		rm -f coreg.out
	
		#	change number of corr. windows to 200 for safer processsing (especially for scenes with water)
		sed -i 's/CC_NWIN.*/CC_NWIN         200/' coarse.dorisin  
		
		ciop-log "INFO" "coarse image correlation for ${sensing_date}"
		doris coarse.dorisin > step_coarse.log
		[ $? -ne 0 ] && return ${ERR_STEP_COARSE}

		#	get all calculated coarse offsets (line 85 - 284) and take out the value which appears most for better calcultion of overall offset
		offsetL=`more coreg.out | sed -n -e 85,284p | awk $'{print $5}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`
		offsetP=`more coreg.out | sed -n -e 85,284p | awk $'{print $6}' | sort | uniq -c | sort -g -r | head -1 | awk $'{print $2}'`

		# 	write the lines with the new overall offset into variable	 
		replaceL=`echo -e "Coarse_correlation_translation_lines: \t" $offsetL`
		replaceP=`echo -e "Coarse_correlation_translation_pixels: \t" $offsetP`	

		# 	replace full line of overall offset
		sed -i "s/Coarse_correlation_translation_lines:.*/$replaceL/" coreg.out
		sed -i "s/Coarse_correlation_translation_pixels:.*/$replaceP/" coreg.out

		######################################
		######check for CPM size##############
		######################################
	
		ciop-log "INFO" "fine image correlation for ${sensing_date}"
		step_coreg_simple
		[ $? -ne 0 ] && return ${ERR_STEP_COREG}

		# prepare dem.dorisin with right dem path
		if [ ! -e ${PROCESS}/INSAR_${master_date}/dem.dorisin ]; then
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
    #    	tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}
        	tar cvfz INSAR_${sensing_date}.tgz ${sensing_date}/slave_res.slc ${sensing_date}/cintminrefdem.raw ${sensing_date}/dem_radar.raw ${sensing_date}/*.out ${sensing_date}/*.res ${sensing_date}/*.log  
        	[ $? -ne 0 ] && return ${ERR_INSAR_SLAVES_TAR}  #${sensing_date}/ref_dem1l.raw 


		ciop-log "INFO" "Publish -a insar_slaves"
		insar_slaves="$( ciop-publish -a ${PROCESS}/INSAR_${master_date}/INSAR_${sensing_date}.tgz )"
		[ $? -ne 0 ] && return ${ERR_INSAR_SLAVES_PUBLISH}
		
		ciop-log "INFO" "Will publish the final output"
		echo "${insar_master},${insar_slaves},${dem}" | ciop-publish -s	
		[ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}

	fi 

done
}
cat | main
exit ${SUCCESS}
