#! /bin/bash
mode=$1

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
ERR_PREMASTER=5
ERR_INSAR_SLAVES=7
ERR_MASTER_SELECT=9
ERR_MASTER_COPY=11
ERR_MASTER_SLC=12
ERR_MASTER_SETUP=13
ERR_INSAR_TAR=15
ERR_INSAR_PUBLISH=17
ERR_FINAL_PUBLISH=19

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
${ERR_INSAR_TAR}) msg="couldn't create tgz archive for publishing";;
${ERR_INSAR_PUBLISH}) msg="couldn't publish new INSAR_MASTER folder";;
${ERR_FINAL_PUBLISH}) msg="couldn't publish final output";;
esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
#[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ -n "${TMPDIR}" ] && chmod -R 777 $TMPDIR
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

dem() {
  local dataset_ref=$1
  local target=$2
  local bbox
  local wkt
 
  wkt="$( ciop-casmeta -f "dct:spatial" "${dataset_ref}" )"
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
# copy INSAR_PREMASTER from input
while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r premaster_slc_ref slc_folders insar_slaves <<< "$line"

	if [ ! -d ${PROCESS}/INSAR_$premaster_date/ ]; then
		
		ciop-copy -O ${PROCESS} ${premaster_slc_ref}
		[ $? -ne 0 ] && return ${ERR_PREMASTER}
	
		premaster_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Pre-Master Date: $premaster_date"
	fi

	ciop-log "INFO" "Retrieve folder: ${insar_slaves}"
	ciop-copy -f -O ${PROCESS}/INSAR_$premaster_date/ $( echo ${insar_slaves} | tr -d "\t")  
	[ $? -ne 0 ] && return ${ERR_INSAR_SLAVES}	
	
done

cd $PROCESS/INSAR_${premaster_date}
master_select > master.date
[ $? -ne 0 ] && return ${ERR_MASTER_SELECT}
master_date=`awk 'NR == 12' master.date | awk $'{print $1}'`
ciop-log "INFO" "Choose SLC from $master_date as final master"


while read line; do

	ciop-log "INFO" "Read input from StdIn"
	IFS=',' read -r premaster_slc_ref slc_folders insar_slaves <<< "$line"
	
	if [[ "`echo ${slc_folders} | basename $line`" == "{$master_date}.tgz" ]]; then
	
		ciop-log "INFO" "Retrieving final master SLC"
		ciop-copy -f -O ${SLC} $( echo ${slc_folders} | tr -d "\t")  
		[ $? -ne 0 ] && return ${ERR_MASTER_COPY}

		cd ${SLC}/${masterdate}
		MAS_WIDTH=`grep WIDTH  ${master_date}.slc.rsc | awk '{print $2}' `
		MAS_LENGTH=`grep FILE_LENGTH  ${master_date}.slc.rsc | awk '{print $2}' `

		ciop-log "INFO" "Running step_master_setup"
		echo "first_l 1" > master_crop.in
		echo "last_l $MAS_LENGTH" >> master_crop.in
		echo "first_p 1" >> master_crop.in
		echo "last_p $MAS_WIDTH" >> master_crop.in
		step_master_setup
		[ $? -ne 0 ] && return ${ERR_MASTER_SETUP} 
	
		ciop-log "INFO" "Archiving the newly created INSAR_$master_date folder"
		cd ${PROCESS}
		tar cvfz INSAR_${master_date}.tgz INSAR_${master_date}
		[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

		# getting the original file url for dem fucntion
		master_ref=`more $master_date.url`
		ciop-log "INFO" "Create DEM"		
		
		#ciop-log "INFO" "Create DEM"
		#dem ${master_ref} ${TMPDIR}/DEM
		#[ $? -ne 0 ] && return ${ERR_DEM}
	
		#head -n 28 ${STAMPS}/DORIS_SCR/timing.dorisin > ${TMPDIR}/INSAR_${master_date}/timing.dorisin
		#cat ${TMPDIR}/DEM/input.doris_dem >> ${TMPDIR}/INSAR_${master_date}/timing.dorisin  
		#tail -n 13 ${STAMPS}/DORIS_SCR/timing.dorisin >> ${TMPDIR}/INSAR_${master_date}/timing.dorisin	

		#step_master_timing
		#[ $? -ne 0 ] && return ${ERR_MASTER_TIMING}

		#ciop-log "INFO" "Publishing the newly created INSAR_$master_date folder"
		#insar_master="$( ciop-publish INSAR_${master_date}.tgz )"
		#[ $? -ne 0 ] && return ${ERR_INSAR_PUBLISH}
	fi	
	
	ciop-log "INFO" "Will publish the final output"
	echo "$insar_master,$slc_folders" | ciop-publish -s	
	[ $? -ne 0 ] && return ${ERR_FINAL_PUBLISH}

done

chmod -R 777 $TMPDIR

}
cat | main
exit ${SUCCESS}

