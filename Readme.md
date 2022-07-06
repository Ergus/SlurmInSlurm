Readme
======

Simple scripts generator to run a nested slurm inside another slurm
cluster.  This script basically gathers all the system's information
and starts a slurm server-clients to be used as a separated instance.

Previous installation
---------------------

A general guide about installing slurm is here
[Install_Slurm](https://southgreenplatform.github.io/trainings/hpc/slurminstallation/)

As our system (nested inside slurm and without root permissions) has
special requirements; we need to take into account:

### Munge

1. Munge needs to be installed for the current user, not need to add group or extra user.

2. Installation form sources, so, download it from here:
   [munge](https://github.com/dun/munge/releases/tag/munge-0.5.15)

3. Munge state needs to be local in every node, but the installation
   and executable may be shared. So we set the state in the
   `/tmp/munge` directory because `/tmp` is generally not shared
   because it is a tmpfs.

3. For munge we define the variables:

```shell
MUNGE_ROOT=${HOME}/install_DIR/munge
MUNGE_STATEDIR=/tmp/munge

./configure --prefix=${MUNGE_ROOT} --localstatedir=${MUNGE_STATEDIR}
```

### MySQL or MariaDB

We try to use the database in a local setup, without any configuration
required. In case your system already has a database, then you may
modify the script database part to not start it but use the existing
one.

### Slurm

After munge install Slurm. The order is ompised because we need to
specify the munge location to slurm at configure time.

1. You don't need to use the same slurm library than the one in your
   system; we actually recommend to use a different version. Ex: Some
   programs inside your new environment will attempt to use the slurm
   library from the global scope; which is very difficult to detect.

2. We set the config directory in a custom location because we need to
   overwrite and regenerate them every time.

```shell
MYSLURM_ROOT=${HOME}/install_DIR/slurm

./configure --prefix=${MYSLURM_ROOT} --sysconfdir=${MYSLURM_ROOT}/slurm-confdir --with-munge=${MUNGE_ROOT}
```

### MPI

Some MPI versions (like MPICH) are linked to the slurm library
including version number; this means that we need two installations,
one for outside to start the services and the other from inside to use
in the environment. For the outer environment there is no difference.

For the nested one:

1. MPICH needs to be downloaded from the sources because *autoreconf*
   fail with relatively (no so) old versions.

2. Before building the inner MPICH you need to assert that it will
   link against your slurm library and not the global one. You need
   this before building MPICH:

```shell
MPICH_ROOT=${HOME}/install_DIR/mpich
export LIBRARY_PATH=${MYSLURM_ROOT}/lib:${LIBRARY_PATH}

./configure --prefix=${MPICH_ROOT} \
	--with-libfabric=embedded --with-hwloc=embedded --disable-fortran \
	--disable-romio --with-datatype-engine=dataloop \
	--enable-ch4-netmod-inline --without-ch4-shmods
```

Usage
-----

And then follow these steps:

1. Export the variable `MYSLURM_ROOT` to the base slurm installation
   directory, we expect `bin`, `sbin`, `slurm-confdir` (can be empty),
   and the other common directories (`include`, `lib`, `doc`...) to be
   there:

```shell
export MYSLURM_ROOT=/some/path/to/slurm
```

2. Get an interactive session in your slurm server, for example:
```shell
salloc -q debug -N 4 --exclusive -t 02:00:00
```

3. Once in the section load the module:
```shell
source myslurm.sh
```

4. Use it. If everything was fine the expected output may show the
   local (server) and remote (slaves) commands and the new environment
   variables created.

   There are two options to access the commands.

	a. Use the wrapper function to keep access to you `parent` slurm
       environment. Ex:
	```shell
	myslurm squeue
	myslurm sinfo
	```

	b. Use the lmod module to access only the new environment. Ex:

	```shell
	module load myslurm
	squeue
	sinfo
	...
	# When you finish you can restore the environment
	module unload myslurm
	```

	The module is loaded by default.
