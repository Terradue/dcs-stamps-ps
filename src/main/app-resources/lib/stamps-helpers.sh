set_env() {
  export SAR_HELPERS_HOME=/opt/sar-helpers/lib/
  . ${SAR_HELPERS_HOME}/sar-helpers.sh

  # shorter temp path
  export TMPDIR=/tmp/$( uuidgen )
  export SLC=${TMPDIR}/SLC
  export VOR_DIR=${TMPDIR}/VOR
  export INS_DIR=${TMPDIR}/INS
  mkdir -p ${INS_DIR}
  mkdir -p ${TMPDIR}/SLC
  mkdir -p ${TMPDIR}/DEM
  return 0
}

get_data() {
  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  enclosure="$( opensearch-client "${ref}" enclosure )"
  res=$?
  # opensearh client doesn't deal with local paths
  [ ${res} -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
  [ ${res} -ne 0 ] && enclosure=${ref}
  
  local_file="$( echo ${enclosure} | ciop-copy -f -U -O ${target} - 2> /dev/null )"
  res=$?
  [ ${res} -ne 0 ] && return ${res}
  echo ${local_file}
}

get_orbit_flag() {
  local orbit_flag
  orbit_flag="$( ciop-getparam orbit )"
  [ ${orbit_flag} != "VOR" ] && [ ${orbit_flag} != "ODR" ] && return 1
  echo ${orbit_flag}
  return 0
}

get_aux() {
  local mission=$1
  local sensing_date=$2
  local orbit_flag=$3
  
  [ ${orbit_flag} == "VOR" ] && {
    local aux_cat="http://catalogue.terradue.int/catalogue/search/DOR_VOR_AX"
    start="$( date -d "${sensing_date} 3 days ago" +%Y-%m-%dT00:00:00 )"
    stop="$( date -d "${sensing_date} 3 days" +%Y-%m-%dT00:00:00 )"
    
    mkdir -p ${TMPDIR}/VOR
  
    opensearch-client -p "time:start=${start}" \
      -p "time:end=${stop}" \
      "${aux_cat}" enclosure > ${TMPDIR}/aux.list
  
    cat ${TMPDIR}/aux.list | while read url; do
    echo ${url} | ciop-copy -O ${TMPDIR}/VOR -
  done

  }
    
  aux_cat="http://catalogue.terradue.int/catalogue/search/ASA_INS_AX"
    
  opensearch-client -p "time:start=${start}" \
    -p "time:end=${stop}" \
    "${aux_cat}" enclosure > ${TMPDIR}/aux.list

  cat ${TMPDIR}/aux.list | while read url; do
    echo ${url} | ciop-copy -O ${TMPDIR}/INS -
  done
   
  
  [ ${orbit_flag} == "ODR" ] && {
    # TODO add ASAR_ODR.tgz, ERS1, ERS2 to /application/aux
    tar -C ${TMPDIR} ${_CIOP_APPLICATION_PATH}/aux/${mission}_ODR.tgz
    
  }
  return 0 
  
}
