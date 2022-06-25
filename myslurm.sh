#!/bin/bash

#SBATCH --time=00:02:00
#SBATCH --exclusive

set -e

# You may change this one to yours
MYSLURM_ROOT=${HOME}/install_mn/slurm

MYSLURM_BIN_DIR=${MYSLURM_ROOT}/bin
MYSLURM_SBIN_DIR=${MYSLURM_ROOT}/sbin

MYSLURM_CONF_DIR=${MYSLURM_ROOT}/slurm-confdir
MYSLURM_CONF_FILE=${MYSLURM_CONF_DIR}/slurm.conf

MYSLURM_VAR_DIR=${MYSLURM_CONF_DIR}/var

MYSLURM_CONF_FILE=${MYSLURM_CONF_DIR}/slurm.conf

# Cleanup and var regeneration
rm -rf ${MYSLURM_VAR_DIR}/slurm*
mkdir -p ${MYSLURM_VAR_DIR}/slurmd ${MYSLURM_VAR_DIR}/slurmctld
echo "" > ${MYSLURM_VAR_DIR}/accounting   # clear the file.
echo "" > ${MYSLURM_VAR_DIR}/slurmctld/job_state   # clear the file.
echo "" > ${MYSLURM_VAR_DIR}/slurmctld/resv_state   # clear the file.

# Generate key (only once)
[ -f myslurm.crt ] ||
	openssl req -x509 -sha256 -days 3650 -newkey rsa -config myslurm.cnf -keyout myslurm.key -out myslurm.crt
[ -f ${MYSLURM_CONF_DIR}/slurm.crt ] || cp myslurm.crt ${MYSLURM_CONF_DIR}/slurm.crt
[ -f ${MYSLURM_CONF_DIR}/slurm.key ] || cp myslurm.key ${MYSLURM_CONF_DIR}/slurm.key

# Get system info: nodes (local and remote), cores, sockets, cpus, memory
NODELIST=$(scontrol show hostname | paste -d" " -s)

MASTER_NODE=$(hostname)                    # Master node

REMOTE_NODES_LIST=(${NODELIST/"${MASTER_NODE}"})  # List of remote nodes (removing master)
REMOTE_NODES_STR=${REMOTE_NODES_LIST[*]}          # "node1 node2 node3"
REMOTE_NODES_STR=${REMOTE_NODES_STR// /,}         # "node1,node2,node3"
REMOTE_NODES_COUNT=${#REMOTE_NODES_LIST[@]}

((REMOTE_NODES_COUNT == 0)) && echo "Error: REMOTE_NODES_COUNT is zero" >&2

NSOCS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l) # Number of CPUS (sockets)
NCPS=$(grep -c "physical id[[:space:]]\+: 0" /proc/cpuinfo) # cores per socket
MEMORY=$(grep MemTotal /proc/meminfo | cut -d' ' -f8)       # memory in KB

{   # Scope to redirect output
	sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
		-e "s|@MYSLURM_CONF_DIR@|${MYSLURM_CONF_DIR}|g" myslurm.conf.base

	echo "SlurmctldHost=${MASTER_NODE}"

	for node in ${REMOTE_NODES_LIST[@]}; do
		echo "NodeName=$node Sockets=${NSOCS} CoresPerSocket=${NCPS} ThreadsPerCore=1 State=Idle"
	done
	echo "PartitionName=malleability Nodes=${REMOTE_NODES_STR} Default=YES MaxTime=INFINITE State=UP"
} > ${MYSLURM_CONF_FILE}

# Print hostname from remotes to stdout ==============================
mpiexec -n ${REMOTE_NODES_COUNT} --hosts=${REMOTE_NODES_STR} hostname | sed -e "s/^/# Remote: /"

# Start the server and clients =======================================
${MYSLURM_SBIN_DIR}/slurmctld -cDvif ${MYSLURM_CONF_FILE} &
mpiexec -n ${REMOTE_NODES_COUNT} --hosts=${REMOTE_NODES_STR} \
		${MYSLURM_SBIN_DIR}/slurmd -cDvf ${MYSLURM_CONF_FILE} &

SLURM_CONF=${MYSLURM_CONF_FILE}
echo "SLURM_CONF=${SLURM_CONF}"

# echo "# From inside"
${MYSLURM_BIN_DIR}/sinfo
${MYSLURM_BIN_DIR}/sbatch -JMyTestJob -N2 sleep 10 &
${MYSLURM_BIN_DIR}/squeue
${MYSLURM_BIN_DIR}/sinfo

aux=$(${MYSLURM_BIN_DIR}/squeue | wc -l);

while [ $aux -gt 1 ]; do
        aux=$( $MYSLURM_BIN_DIR/squeue | wc -l );
        echo "$aux jobs remaining...";
        sleep 2;
done

echo "Finishing...";
${MYSLURM_BIN_DIR}/sacct

