Readme
======

Simple scripts generator to run a nested slurm inside another slurm
cluster.  This script basically gathers all the system's information
and starts a slurm server-clients to be used as a separated instance.

Previous installation
---------------------

A general guide about installing slurm is here
[Install_Slurm](https://southgreenplatform.github.io/trainings/hpc/slurminstallation/)

Our system (nested inside slurm and without root permissions) has
special requirements; we need to take into account:

### Munge

1. Munge needs to be installed for the current user, not need to add
   group or extra user.

2. Installation from sources, so, download it from here:
   [munge](https://github.com/dun/munge/releases/tag/munge-0.5.15)

3. Munge state needs to be local in every node, but the installation
   and executable may be shared. So we set the state in the
   `/tmp/${USER}/munge` directory because `/tmp` is not shared; (it is a
   *tmpfs* local to every node).

4. For munge we define the variables:

```shell
MUNGE_ROOT=${HOME}/install_DIR/munge
MUNGE_STATEDIR=/tmp/${USER}/munge

./configure --prefix=${MUNGE_ROOT} --localstatedir=${MUNGE_STATEDIR}
```

### MySQL or MariaDB

We try to use the database in a local setup, without any configuration
required. In case your system already has a database, then you may
modify the script database variables to not start it but use the
existing one. We assume here you have a mysql installation in your
path.

- We recommend the version: mariadb-10.6.8-linux-systemd-x86_64

- Out script will use a socket inside **/tmp/${USER}** you can check
  its creation in case of error and attempt to connect to it.

### Slurm

After munge and MariaDB install Slurm. The order is important because
we need to specify the munge location to slurm at configure time.

1. You don't need to use the same slurm library than the one in your
   system; we actually recommend to use a different version. Ex: Some
   programs inside your new environment will attempt to use the slurm
   library from the global scope; which is very difficult to detect.

2. We set the config directory in a custom location because we need to
   overwrite and regenerate them every time.

3. Check that the MariaDB **lib** directory is in the LD_LIBRARY_PATH
   because slurm will attempt to link with it. If it is not then the
   mysql plugin won't be be compiled silently and slurmdbd will fail
   to start latter.

```shell
MYSLURM_ROOT=${HOME}/install_DIR/slurm

./configure --prefix=${MYSLURM_ROOT} \
	    --sysconfdir=${MYSLURM_ROOT}/slurm-confdir \
	    --with-munge=${MUNGE_ROOT}
```

### MPI

It is very likely that your system already have some mpi library
installed. And the outer slurm provide then an **srun** command. We
require that.

Some MPI versions (like MPICH) are linked to the slurm library
including version number; this means that we need a second
installation from inside the nested session to use in our environment.

To install the nested MPI:

1. The nested slurm needs to be build AFTER loading the module for the
   first time with `MPICH_ROOT` unset.

2. MPICH needs to be downloaded from the sources because *autoreconf*
   fail with relatively (no so) old versions.

3. Before building the inner MPICH you need to assert that it will
   link against your slurm library and not the global one, that's why
   it needs to be built in a nested session:

```shell
salloc -N 1 --exclusive -t 02:00:00 # In the nested slurm

MPICH_ROOT=${HOME}/install_DIR/mpich
export LIBRARY_PATH=${MYSLURM_ROOT}/lib:${LIBRARY_PATH}

./configure --prefix=${MPICH_ROOT} --with-libfabric=embedded \
	    --with-hwloc=embedded  --with-datatype-engine=dataloop \
	    --enable-ch4-netmod-inline --without-ch4-shmods
```

Usage
-----

To use this module there are two simple alternatives:

1. If all the installation is fine, then the next time you just need
   to do:
```shell
salloc -q debug -N XXX --exclusive -t 02:00:00 # In the external slurm
source myslurm.sh
```

This will start the server and sets the current environment to use the
new nested slurm only.

This step also creates a script: **/tmp/${USER}/myslurm_load.sh** in
the **/tmp** directory of the master node. (You know the master node
reading the output of this step)

2. If the server is already running but you want to access it from
   another shell you just need to do:
```shell
ssh MASTERNODE
source /tmp/${USER}/myslurm_load.sh
```

After this you are in the nested session and you can *sbatch*, *srun*,
*salloc* and so on.
