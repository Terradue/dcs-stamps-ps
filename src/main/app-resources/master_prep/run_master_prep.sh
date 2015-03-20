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

export RAW=${TMPDIR}/RAW

# PROCESS folder
export PROCESS=${TMPDIR}/PROCESS

#--------------------------------
#	2) Error Handling	
#--------------------------------

# define the exit codes
SUCCESS=0
ERR_ORBIT_FLAG=5
ERR_SCENE_EMPTY=7
ERR_SETUP_PREMASTER=9
ERR_MAKE_ORBITS=11
ERR_MAKE_COARSE=13
ERR_SETUP_MASTER=15

# add a trap to exit gracefully
cleanExit() {
local retval=$?
local msg
msg=""
case "${retval}" in
${SUCCESS}) msg="Processing successfully concluded";;
${ERR_ORBIT_FLAG}) msg="Failed to determine which orbit files to use (check your application.xml)";;
${ERR_SCENE_EMPTY}) msg="Failed to retrieve scene";;
${ERR_SETUP_PREMASTER}) msg="Failed to set up preliminary Master )";;
${ERR_MAKE_ORBITS}) msg="Failed to interpolate orbits (make_orbit step)";;
${ERR_MAKE_COARSE}) msg="Failed to do coarse coregistration";;
${ERR_SETUP_MASTER}) msg="Failed to set up the Master scene";;
esac
[ "${retval}" != "0" ] && ciop-log "ERROR" \
"Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
[ -n "${TMPDIR}" ] && rm -rf ${TMPDIR}
[ "${mode}" == "test" ] && return ${retval} || exit ${retval}
}
trap cleanExit EXIT

#--------------------------------
#	3) Main Function	
#--------------------------------
main() {
local res

# Input
while read line; do 
	ciop-copy -o ${PROCESS} ${line}
done

ls -1 ${PROCESS} *tgz > list_tgz
while read line;do
	tar -xvf ${PROCESS}/
done < list_tgz

cd $PROCESS/SLC	
PRE_MASTER=`ls -1 | awk 'NR == 1'` #VALID???

# get pixel & lines for the image
# might be done for every image creating a YYYYMMDD.proc in every SLC/YYYYMMDD folder
MAS_WIDTH=`grep WIDTH $PRE_MASTER.slc.rsc | awk '{print $2}' `
MAS_LENGTH=`grep FILE_LENGTH $PRE_MASTER.slc.rsc | awk '{print $2}' `
#MEAN_PXL_RNG=`expr $MAS_WIDTH / 2`

# 	Focalise Master Scene
cd $PROCESS/SLC/$PRE_MASTER

#-----------------------------------------------------
# create a master_crop.in with full extent and set-up preliminary INSAR folder 
#-----------------------------------------------------

echo "first_l 1" > master_crop.in
echo "last_l $MAS_LENGTH" >> master_crop.in
echo "first_p 1" >> master_crop.in
echo "last_p $MAS_WIDTH" >> master_crop.in

# set up preliminary master
step_master_setup
[ $? -ne 0 ] && return ${ERR_SETUP_PREMASTER}

# go to preliminary insar folder
cd $PROCESS/INSAR_$PRE_MASTER

# make orbits
make_orbits
[ $? -ne 0 ] && return ${ERR_MAKE_ORBITS}

make_coarse 

#while read line; do
	
#	cd $line
#	# code snippet taken from step_coarse original
#	cp $DORIS_SCR/coarse.dorisin . 
#	doris coarse.dorisin > step_coarse.log
#	[ $? -ne 0 ] && return ${ERR_MAKE_COARSE}
#	cd ../
#done

#
master_select > master.txt
MASTER=`awk 'NR == 12' master.txt | awk $'{print $1}'` # check if it is always line 12 with most suited master

#---------------------------------------------------------------------------------------------
# 	10) Set-up final INSAR folder (same as 7, but for best master) 
#---------------------------------------------------------------------------------------------

cd $PROCESS/SLC/$MASTER

# 	get lines and pixels from final master
MAS_WIDTH=`grep WIDTH $MASTER.slc.rsc | awk '{print $2}' `
MAS_LENGTH=`grep FILE_LENGTH $MASTER.slc.rsc | awk '{print $2}' `

# 	master setup
touch master_crop.in
#echo "first_l 1" > master_crop.in
#echo "last_l $MAS_LENGTH" >> master_crop.in
#echo "first_p 1" >> master_crop.in
#echo "last_p $MAS_WIDTH" >> master_crop.in

echo "first_l 10000" > master_crop.in
echo "last_l 15000" >> master_crop.in
echo "first_p 2000" >> master_crop.in
echo "last_p 4000" >> master_crop.in


step_master_setup
[ $? -ne 0 ] && return ${ERR_SETUP_MASTER}


}
cat | main
#res=$?
#[ ${res} -ne 0 ] && exit ${res}
#[ "${mode}" != "test" ] && exit 0
exit ${SUCCESS}
