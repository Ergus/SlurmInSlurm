#!/bin/bash

#SBATCH --time=00:02:00
#SBATCH --exclusive

if [[ $0 == ${BASH_SOURCE[0]} ]]; then
    echo "Don't run $0, source it" >&2
    exit 1
fi

# Hardcoded info ==============================================
# You may change this one to yours
MYSLURM_ROOT=${HOME}/install_mn/slurm
MYSLURM_USER=${USER}
MYSLURM_DBD_PORT=7101

MYSLURM_TMP=/tmp/${USER}

MARIADB_ROOT=${HOME}/install_mn/mariadb
MARIADB_PORT=7100
MYSQL_UNIX_PORT=${MYSLURM_TMP}/mysql.sock

rm -rf ${MYSLURM_TMP}
mkdir ${MYSLURM_TMP}

MUNGE_ROOT=${HOME}/install_mn/munge
MUNGE_STATEDIR=${MYSLURM_TMP}/munge

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
  echo "# Waiting mysql socket: ${MYSQL_UNIX_PORT}"
  sleep 1
done
echo "# Waiting mysql done"

MARIADB_CMD="GRANT ALL ON slurm_acct_db.* TO '${MYSLURM_USER}'@'localhost' WITH GRANT OPTION;"
MARIADB_CMD+="CREATE DATABASE slurm_acct_db;"
MARIADB_CMD+="FLUSH PRIVILEGES;"

mysql -u ${MYSLURM_USER} --port=${MARIADB_PORT} --protocol=SOCKET \
	  --execute="${MARIADB_CMD}"

# Generate files =====================================================

# Generate the munge key if not set.
if ! [ -f ${MUNGE_ROOT}/etc/munge/munge.key ]; then
	echo "# Generating munge key: ${MUNGE_ROOT}/etc/munge/munge.key"
	dd if=/dev/random bs=1 count=1024 > ${MUNGE_ROOT}/etc/munge/munge.key
	chmod 0400 ${MUNGE_ROOT}/etc/munge/munge.key
fi

# Create MYSLURM_CONF_FILE
NODENAMES=$(scontrol show hostlistsorted ${MYSLURM_SLAVES})

NSOCS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l) # Number of CPUS (sockets)
NCPS=$(grep -c "physical id[[:space:]]\+: 0" /proc/cpuinfo) # cores per socket

MEMORY=$(grep MemTotal /proc/meminfo | cut -d' ' -f8)       # memory in KB
REALMEM=$(((MEMORY / 1024 / 1024) * 1024))

echo "# Generating slurm config: ${MYSLURM_CONF_DIR}/slurm.conf"
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

echo "# Generating topology: ${MYSLURM_CONF_DIR}/topology.conf"
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

echo "# Generating slurmdbd config: ${MYSLURM_CONF_DIR}/slurmdbd.conf"
sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_USER@|${MYSLURM_USER}|g" \
	-e "s|@MYSLURM_DBD_PORT@|${MYSLURM_DBD_PORT}|g" \
	-e "s|@MARIADB_PORT@|${MARIADB_PORT}|g" \
	slurmdbd.conf.base > ${MYSLURM_CONF_DIR}/slurmdbd.conf

chmod 600 ${MYSLURM_CONF_DIR}/slurmdbd.conf

# Wrapper
echo "# Generating wrapper: ${MYSLURM_CONF_DIR}/mywrapper.sh"
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

# Create the load script to use in other shells.
echo "# Generating loader: ${MYSLURM_TMP}/myslurm_load.sh"
sed -e "s|@MYSLURM_ROOT@|${MYSLURM_ROOT}|g" \
	-e "s|@MYSLURM_CONF_DIR@|${MYSLURM_CONF_DIR}|g" \
	-e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
	-e "s|@MYSLURM_NSLAVES@|${MYSLURM_NSLAVES}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_SLAVES@|${MYSLURM_SLAVES}|g" \
	-e "s|@MYMPICH_ROOT@|${MYMPICH_ROOT}|g" \
	myslurm_load.sh.base > ${MYSLURM_TMP}/myslurm_load.sh

# Remove mpich variables if not available
[[ -z ${MYMPICH_ROOT} ]] && \
	sed -i '/^# MPICH/,/^# EOF/{//!d;};' ${MYSLURM_TMP}/mympich_load.sh

# Print information ==================================================
echo "# Master: ${MYSLURM_MASTER}"
# This also checks that the external srun command is working fine...
# Information will be printed again latter to check affinity from
# inside the mywrapper If wrapper affinity is not set properly, then
# slurmd initialization gets a wrong taskset at initialization time
# and uses that bad for the processes it executes.
srun -n $((MYSLURM_NSLAVES + 1)) -c $((NSOCS * NCPS)) hostname | sed -e "s/^/# Node: /"

# Start the servers and clients ======================================
srun -n $((MYSLURM_NSLAVES + 1)) -c $((NSOCS * NCPS)) ${MYSLURM_CONF_DIR}/mywrapper.sh &

# Exports ============================================================
# Exports environment at the end to avoid modifying the environment

env | grep "MYSLURM" | sed -e "s/^/# /"
echo "# MYMPICH_ROOT=${MYMPICH_ROOT}"

# load the environment here. We need it to call sacctmgr.
source ${MYSLURM_TMP}/myslurm_load.sh

echo "# Create account"
sacctmgr -i create user name=${MYSLURM_USER} DefaultAccount=root AdminLevel=Admin

echo "# Test that internal srun works:"
srun -n ${MYSLURM_NSLAVES} -c $((NSOCS * NCPS)) hostname | sed -e "s/^/# Node: /"
