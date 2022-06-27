Readme
======

Simple scripts generator to run a nested slurm inside another slurm
cluster.  This script basically gathers all the system's information
and starts a slurm server-clients to be used as a separated instance.

Usage
-----

To use this module you need to have installed slurm (which is beyond
the scope of this package)

And then follow these steps:

1. Export the variable `MYSLURM_ROOT` to the base slurm installation
   directory, we expect `bin`, `sbin`, `slurm-confdir` (can be empty),
   and the other common directories (`include`, `lib`, `doc`...) to be
   there:

  ```bash
   export MYSLURM_ROOT=/some/path/to/slurm
   ```

2. Get an interactive session in your slurm server, for example:
   ```bash
   salloc -q debug -N 4 --exclusive -t 02:00:00
   ```

3. Once in the section load the module:
   ```bash
   source myslurm.sh
   ```

4. Use it. If everything was fine the expected output may show the
   local (server) and remote (slaves) commands and the new environment
   variables created.

	There are two options to access the commands.

	a. Use the wrapper function to keep access to you `parent` slurm
       environment. Ex:

	   ```bash
	   myslurm squeue
	   myslurm sinfo
	   ```

	b. Use the lmod module to access only the new environment.Ex:

		```bash
		module load myslurm
		squeue
		sinfo
		...
		# When you finish you can restore the environment
		module unload myslurm
		```

