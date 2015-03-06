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

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_PREMASTER}) msg="couldn't retrieve ";; 

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

while read line; do

	ciop-log "INFO" "Processing input: $line"
        IFS=',' read -r insar_master slc_folders <<< "$line"

	if [ ! -d ${PROCESS}/INSAR_$master_date/ ]; then
		ciop-copy -O ${PROCESS} ${insar_master}
		[ $? -ne 0 ] && return ${ERR_MASTER_RETRIEVE}
		
		master_date=`basename ${PROCESS}/I* | cut -c 7-14` 	
		ciop-log "INFO" "Final Master Date: $master_date"

		cd ${PROCESS}	
		tar xvfz INSAR_${master_date}.tgz 
		[ $? -ne 0 ] && return ${ERR_INSAR_TAR}

		cd INSAR_${master_date}

		# get master_ref
		master_ref=`more /application/inputs/input.list | grep $master_date` # check if input.list available from outside
				
		ciop-log "INFO" "Create DEM"
		dem ${master_ref} ${TMPDIR}/DEM
		[ $? -ne 0 ] && return ${ERR_DEM}

	  	head -n 28 ${STAMPS}/DORIS_SCR/timing.dorisin > ${TMPDIR}/INSAR_${master_date}/timing.dorisin
		cat ${TMPDIR}/DEM/input.doris_dem >> ${TMPDIR}/INSAR_${master_date}/timing.dorisin  
		tail -n 13 ${STAMPS}/DORIS_SCR/timing.dorisin >> ${TMPDIR}/INSAR_${master_date}/timing.dorisin

		step_master_timing
		[ $? -ne 0 ] && return ${ERR_MASTER_TIMING} 
	fi
	
	ciop-copy -O ${SLC} ${slc_folders}
	[ $? -ne 0 ] && return ${ERR_SLC_RETRIEVE}

	# substitute file in master.res & slave.res 

