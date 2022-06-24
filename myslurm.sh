#!/bin/bash

#SBATCH --time=00:02:00
#SBATCH --exclusive

set -e

MYSLURM_ROOT=${HOME}/install_mn/slurm

MYSLURM_BIN_DIR=${MYSLURM_ROOT}/bin
MYSLURM_SBIN_DIR=${MYSLURM_ROOT}/sbin
MYSLURM_CONF_DIR=${MYSLURM_ROOT}/slurm-confdir
MYSLURM_VAR_DIR=${MYSLURM_ROOT}/var

MYSLURM_CONF_FILE=${MYSLURM_CONF_DIR}/slurm.conf

# Cleanup
rm -rf ${MYSLURM_VAR_DIR}/slurm*
> ${MYSLURM_VAR_DIR}/accounting   # clear the file.
mkdir ${MYSLURM_VAR_DIR}/slurmd

# Gather system
NODELIST=$(scontrol show hostname | paste -d" " -s)

MASTER_NODE=$(hostname)                    # Master node

REMOTE_NODES_LIST=(${NODELIST/"${MASTER_NODE}"})  # List of remote nodes (removing master)
REMOTE_NODES_STR=${REMOTE_NODES_LIST[*]}               # "node1 node2 node3"
REMOTE_NODES_STR=${REMOTE_NODES_STR// /,}         # "node1,node2,node3"
REMOTE_NODES_COUNT=${#REMOTE_NODES_LIST[@]}

NSOCS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l) # Number of CPUS (sockets)
NCPS=$(grep -c "physical id[[:space:]]\+: 0" /proc/cpuinfo) # cores per socket
MEMORY=$(grep MemTotal /proc/meminfo | cut -d' ' -f8)       # memory in KB

# Create MYSLURM_CONF_FILE ===========================================

{
	sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" slurm.conf.base

	echo "DefMemPerNode=$((MEMORY / 1024))"
	echo "SlurmctldHost=${MASTER_NODE}"

	for node in ${REMOTE_NODES_LIST[@]}; do
		echo "NodeName=$node Sockets=${NSOCS} CoresPerSocket=${NCPS} ThreadsPerCore=1 State=Idle"
	done
	echo "PartitionName=malleability Nodes=${REMOTE_NODES_STR} Default=YES MaxTime=INFINITE State=UP"
} > ${MYSLURM_CONF_FILE}

# Print hostname from remotes to stdout ==============================
mpiexec -n ${REMOTE_NODES_COUNT} --hosts=${REMOTE_NODES_STR} hostname | sed -e "s/^/# Remote: /"

# Start the server and clients =======================================
echo "HEE ${MYSLURM_SBIN_DIR}/slurmctld"
echo "HOO ${MYSLURM_SBIN_DIR}/slurmd"
${MYSLURM_SBIN_DIR}/slurmctld -cDvf ${MYSLURM_CONF_FILE} &
mpiexec -n ${REMOTE_NODES_COUNT} --hosts=${REMOTE_NODES_STR} ${MYSLURM_SBIN_DIR}/slurmd -cDvf ${MYSLURM_CONF_FILE} &

# echo "# From inside"
$MYSLURM_BIN_DIR/sinfo
$MYSLURM_BIN_DIR/sbatch -JMyTestJob -N2 ./HEREYOURJOB.sh &
$MYSLURM_BIN_DIR/squeue
$MYSLURM_BIN_DIR/sinfo

aux=$(${MYSLURM_BIN_DIR}/squeue | wc -l);

while [ $aux -gt 1 ]; do
        aux=$( $MYSLURM_BIN_DIR/squeue | wc -l );
        echo "$aux jobs remaining...";
        sleep 10;
done

echo "Finishing...";
$MYSLURM_BIN/sacct

