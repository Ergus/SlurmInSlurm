#!/bin/bash

#SBATCH --time=00:02:00
#SBATCH --exclusive

if [[ $0 == ${BASH_SOURCE[0]} ]]; then
    echo "Don't run $0, source it" >&2
    exit 1
fi

MUNGE_ROOT=${HOME}/install_mn/munge
MUNGE_STATEDIR=/tmp/munge

# You may change this one to yours
MYSLURM_ROOT=${HOME}/install_mn/slurm

MYSLURM_CONF_DIR=${MYSLURM_ROOT}/slurm-confdir
[[ -d "${MYSLURM_CONF_DIR}" ]] || mkdir ${MYSLURM_CONF_DIR}

MYSLURM_VAR_DIR=${MYSLURM_CONF_DIR}/var
[[ -d "${MYSLURM_VAR_DIR}" ]] || mkdir ${MYSLURM_VAR_DIR}

# Cleanup and var regeneration
rm -rf ${MYSLURM_VAR_DIR}/slurm*
mkdir -p ${MYSLURM_VAR_DIR}/{slurmd,slurmctld,myslurm}

echo "" > ${MYSLURM_VAR_DIR}/accounting   # clear the file.

# Get system info: nodes (local and remote), cores, sockets, cpus, memory
MYSLURM_MASTER=$(hostname)                    # Master node
NODELIST=$(scontrol show hostname | paste -d" " -s)

REMOTE_LIST=(${NODELIST/"${MYSLURM_MASTER}"})       # List of remote nodes (removing master)
_SLURM_SLAVES=${REMOTE_LIST[*]}                    # "node1 node2 node3"

MYSLURM_SLAVES=${_SLURM_SLAVES// /,}        # "node1 node2 node3"
MYSLURM_NSLAVES=${#REMOTE_LIST[@]}           # number of slaves

if ((MYSLURM_NSLAVES == 0)); then
	echo "Error: MYSLURM_NSLAVES is zero (are you in the login node?)" >&2
	return 1
fi

NSOCS=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l) # Number of CPUS (sockets)
NCPS=$(grep -c "physical id[[:space:]]\+: 0" /proc/cpuinfo) # cores per socket
MEMORY=$(grep MemTotal /proc/meminfo | cut -d' ' -f8)       # memory in KB

# Generate files =====================================================

MYSLURM_CONF_FILE=${MYSLURM_CONF_DIR}/slurm.conf
{ # Create MYSLURM_CONF_FILE
	sed -e "s|@MYSLURM_VAR_DIR@|${MYSLURM_VAR_DIR}|g" \
		-e "s|@MYSLURM_CONF_DIR@|${MYSLURM_CONF_DIR}|g" myslurm.conf.base

	echo "SlurmctldHost=${MYSLURM_MASTER}"

	for node in ${REMOTE_LIST[@]}; do
		mkdir ${MYSLURM_VAR_DIR}/slurmd.${node}
		echo "NodeName=$node Sockets=${NSOCS} CoresPerSocket=${NCPS} ThreadsPerCore=1 State=Idle"
	done
	echo "PartitionName=malleability Nodes=ALL Default=YES MaxTime=INFINITE State=UP"
	echo ""
} > ${MYSLURM_CONF_FILE}

# Copy the lua lmod
[[ -f ${MYSLURM_VAR_DIR}/myslurm/personal.lua ]] ||
	cp myslurm.lua ${MYSLURM_VAR_DIR}/myslurm/personal.lua

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


# Wrapper
sed -e "s|@MUNGE_STATEDIR@|${MUNGE_STATEDIR}|g" \
	-e "s|@MUNGE_ROOT@|${MUNGE_ROOT}|g" \
	-e "s|@MYSLURM_MASTER@|${MYSLURM_MASTER}|g" \
	-e "s|@MYSLURM_ROOT@|${MYSLURM_ROOT}|g" \
	-e "s|@MYSLURM_CONF_FILE@|${MYSLURM_CONF_FILE}|g" \
	mywrapper.sh.base > ${MYSLURM_CONF_DIR}/mywrapper.sh

chmod a+x ${MYSLURM_CONF_DIR}/mywrapper.sh

# Print hostname from remotes to stdout ==============================
echo "# Master: ${MYSLURM_MASTER}"
mpiexec -n ${MYSLURM_NSLAVES} --hosts=${MYSLURM_SLAVES} hostname | sed -e "s/^/# SLAVE: /"

# Start the server and client ========================================
mpiexec -n $((MYSLURM_NSLAVES + 1)) --hosts=${NODELIST// /,} ${MYSLURM_CONF_DIR}/mywrapper.sh &

# Use this command to call slurm commands example: myslurm squeue
myslurm () {
	SLURM_CONF=${MYSLURM_CONF_FILE} ${MYSLURM_ROOT}/bin/$@
}

env | grep "MYSLURM" | sed -e "s/^/# /"

# Exports environment at the end to avoid modifying the environment
export MYSLURM_ROOT=${MYSLURM_ROOT}
export MYSLURM_CONF_DIR=${MYSLURM_CONF_DIR}
export MYSLURM_CONF_FILE=${MYSLURM_CONF_FILE}
export MYSLURM_VAR_DIR=${MYSLURM_VAR_DIR}

export MYSLURM_MASTER=${MYSLURM_MASTER}
export MYSLURM_SLAVES=${MYSLURM_SLAVES}        # "node1 node2 node3"
export MYSLURM_NSLAVES=${MYSLURM_NSLAVES}      # number of slaves

[[ "${MODULEPATH}" =~ "${MYSLURM_VAR_DIR}" ]] ||
	export MODULEPATH=${MYSLURM_VAR_DIR}:${MODULEPATH}

export -f myslurm
# # echo "# From inside"

myslurm sinfo
myslurm squeue

module load myslurm
