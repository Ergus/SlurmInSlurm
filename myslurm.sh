#!/bin/bash

#SBATCH --time=00:02:00
#SBATCH --exclusive

if [[ $0 == ${BASH_SOURCE[0]} ]]; then
    echo "Don't run $0, source it" >&2
    exit 1
fi

# Hardcoded info ==============================================
MARIADB_ROOT=${HOME}/install_mn/mariadb
MARIADB_PORT=7100

MUNGE_ROOT=${HOME}/install_mn/munge
MUNGE_STATEDIR=/tmp/munge

# You may change this one to yours
MYSLURM_ROOT=${HOME}/install_mn/slurm
MYSLURM_USER=bsc28860
MYSLURM_DBD_PORT=7101

# MPICH
MYMPICH_ROOT=${HOME}/install_mn/mpich_myslurm

# Get system info ====================================================
MYSLURM_MASTER=$(hostname)                     # Master node
MYSLURM_IP=$(hostname -i)                      # Master ip
NODELIST=$(scontrol show hostname | paste -d" " -s)

REMOTE_LIST=(${NODELIST/"${MYSLURM_MASTER}"})  # List of remote nodes (removing master)
_SLURM_SLAVES=${REMOTE_LIST[*]}                # "node1 node2 node3"

MYSLURM_SLAVES=${_SLURM_SLAVES// /,}           # "node1,node2,node3"
MYSLURM_NSLAVES=${#REMOTE_LIST[@]}             # number of slaves

if ((MYSLURM_NSLAVES == 0)); then
	echo "Error: MYSLURM_NSLAVES is zero (are you in the login node?)" >&2
	return 1
fi

# Create and clean directories and database ==========================
MYSLURM_CONF_DIR=${MYSLURM_ROOT}/slurm-confdir
[[ -d "${MYSLURM_CONF_DIR}" ]] || mkdir ${MYSLURM_CONF_DIR}

MYSLURM_VAR_DIR=${MYSLURM_CONF_DIR}/var
[[ -d "${MYSLURM_VAR_DIR}" ]] || mkdir ${MYSLURM_VAR_DIR}

# Cleanup and var regeneration
rm -rf ${MYSLURM_VAR_DIR}/slurm*
mkdir -p ${MYSLURM_VAR_DIR}/{slurmd,slurmctld}

echo "" > ${MYSLURM_VAR_DIR}/accounting        # clear the file.

for node in ${REMOTE_LIST[@]}; do
	mkdir ${MYSLURM_VAR_DIR}/slurmd.${node}
done

# Database ===========================================================
MARIADB_DATA=${MYSLURM_VAR_DIR}/mariadb-data
rm -rf ${MARIADB_DATA} && mkdir ${MARIADB_DATA}
rm -rf ${MYSQL_UNIX_PORT}

# Create storage
mysql_install_db --verbose \
				 --datadir=${MARIADB_DATA} \
				 --basedir=${MARIADB_ROOT} \
				 --user=${MYSLURM_USER} \
				 --port=${MARIADB_PORT}

# Start server
mysqld_safe --verbose \
			--datadir=${MARIADB_DATA} \
			--basedir=${MYSLURM_ROOT} \
			--user=${MYSLURM_USER} \
			--port=${MARIADB_PORT} &

# Start server
while ! [[ -S ${MYSQL_UNIX_PORT} ]] ; do
  echo "Waiting mysql socket: ${MYSQL_UNIX_PORT}"
  sleep 1
done
echo "Waiting mysql done"

MARIADB_CMD="GRANT ALL ON slurm_acct_db.* TO '${MYSLURM_USER}'@'localhost' WITH GRANT OPTION;"
MARIADB_CMD="GRANT ALL ON slurm_acct_db.* TO '${MYSLURM_USER}'@'localhost' WITH GRANT OPTION;"
MARIADB_CMD+="CREATE DATABASE slurm_acct_db;"
MARIADB_CMD+="FLUSH PRIVILEGES;"

mysql -u ${MYSLURM_USER} --port=${MARIADB_PORT} --protocol=SOCKET \
	  --execute="${MARIADB_CMD}"

# Generate files =====================================================

# Create MYSLURM_CONF_FILE
NODENAMES=$(scontrol show hostlistsorted ${MYSLURM_SLAVES})

NSOCS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l) # Number of CPUS (sockets)
NCPS=$(grep -c "physical id[[:space:]]\+: 0" /proc/cpuinfo) # cores per socket

MEMORY=$(grep MemTotal /proc/meminfo | cut -d' ' -f8)       # memory in KB
REALMEM=$(((MEMORY / 1024 / 1024) * 1024))

sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
	-e "s|@MYSLURM_CONF_DIR@|${MYSLURM_CONF_DIR}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_USER@|${MYSLURM_USER}|g" \
	-e "s|@MYSLURM_DBD_PORT@|${MYSLURM_DBD_PORT}|g" \
	-e "s|@REALMEM@|${REALMEM}|g" \
	-e "s|@NODENAMES@|${NODENAMES}|g" \
	-e "s|@NSOCS@|${NSOCS}|g" \
	-e "s|@MYSLURM_IP@|${MYSLURM_IP}|g" \
	-e "s|@NCPS@|${NCPS}|g" \
	slurm.conf.base > ${MYSLURM_CONF_DIR}/slurm.conf

{ # Topology for marenostrum4
	declare -A myarray=()
	for node in ${REMOTE_LIST[@]}; do
		if [[ ${node} =~ ^(s[0-9]+r[0-9]+)b([0-9]+)$ ]]; then
			name=${BASH_REMATCH[1]}opasw$(( 1 + BASH_REMATCH[2] / 24))
			myarray[${name}]+="${node},"
		else
			echo "Error: Node ${node} didn't match" >&2
		fi
	done

	for i in ${!myarray[@]}; do
		echo "SwitchName=${i} Nodes=$(scontrol show hostlistsorted ${myarray[${i}]})"
	done
	switches=${!myarray[*]}
	echo "SwitchName=troncal Switches=$(scontrol show hostlistsorted ${switches// /,})"

} > ${MYSLURM_CONF_DIR}/topology.conf

sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_USER@|${MYSLURM_USER}|g" \
	-e "s|@MYSLURM_DBD_PORT@|${MYSLURM_DBD_PORT}|g" \
	-e "s|@MARIADB_PORT@|${MARIADB_PORT}|g" \
	slurmdbd.conf.base > ${MYSLURM_CONF_DIR}/slurmdbd.conf

chmod 600 ${MYSLURM_CONF_DIR}/slurmdbd.conf

# Wrapper
sed -e "s|@MUNGE_STATEDIR@|${MUNGE_STATEDIR}|g" \
	-e "s|@MUNGE_ROOT@|${MUNGE_ROOT}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_USER@|${MYSLURM_USER}|g" \
	-e "s|@MYSLURM_DBD_PORT@|${MYSLURM_DBD_PORT}|g" \
	-e "s|@MYSLURM_ROOT@|${MYSLURM_ROOT}|g" \
	-e "s|@MYSLURM_CONF_DIR@|${MYSLURM_CONF_DIR}|g" \
	-e "s|@MARIADB_ROOT@|${MARIADB_ROOT}|g" \
	-e "s|@MARIADB_DATA@|${MARIADB_DATA}|g" \
	-e "s|@MARIADB_PORT@|${MARIADB_PORT}|g" \
	mywrapper.sh.base > ${MYSLURM_CONF_DIR}/mywrapper.sh

chmod a+x ${MYSLURM_CONF_DIR}/mywrapper.sh

# Print information ==================================================
echo "# Master: ${MYSLURM_MASTER}"
mpiexec -n ${MYSLURM_NSLAVES} --hosts=${MYSLURM_SLAVES} hostname | sed -e "s/^/# SLAVE: /"

env | grep "MYSLURM" | sed -e "s/^/# /"

# Start the servers and clients ======================================
mpiexec -n $((MYSLURM_NSLAVES + 1)) --hosts=${NODELIST// /,} ${MYSLURM_CONF_DIR}/mywrapper.sh &

# Exports ============================================================

# Exports environment at the end to avoid modifying the environment
export MYSLURM_ROOT=${MYSLURM_ROOT}
export MYSLURM_CONF_DIR=${MYSLURM_CONF_DIR}
export MYSLURM_VAR_DIR=${MYSLURM_VAR_DIR}
export MYSLURM_NSLAVES=${MYSLURM_NSLAVES}      # number of slaves

export MYSLURM_MASTER=${MYSLURM_MASTER}
export MYSLURM_SLAVES=${MYSLURM_SLAVES}        # "node1 node2 node3"
export MYMPICH_ROOT=${MYMPICH_ROOT}            # mpich

for mod in *.lua; do
	dirname=${MYSLURM_VAR_DIR}/${mod%.lua}
	[[ -d ${dirname} ]] || mkdir ${dirname}
	[[ -f ${dirname}/personal.lua ]] || cp ${mod} ${dirname}/personal.lua
	echo "Creating ${dirname}/personal.lua"
done

[[ "${MODULEPATH}" =~ "${MYSLURM_VAR_DIR}" ]] ||
	export MODULEPATH=${MYSLURM_VAR_DIR}:${MODULEPATH}


myslurm () {
	SLURM_CONF=${MYSLURM_CONF_DIR}/slurm.conf ${MYSLURM_ROOT}/bin/$@
}
export -f myslurm
# # echo "# From inside"

myslurm sinfo
myslurm squeue

module load myslurm mympich

#create account 
sacctmgr -i create user name=${MYSLURM_USER=bsc28860} DefaultAccount=root AdminLevel=Admin
