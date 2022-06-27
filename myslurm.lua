--
-- Author: Jimmy Aguilar Mena
-- Date: Oct 14, 2019
--

local PROG_NAME = "myslurm"
local PROG_VERSION = "personal"
local PROG_HOME = os.getenv("MYSLURM_ROOT")

if (not PROG_HOME ) then
   LmodError("Environment variable MYSLURM_ROOT is not set" )
end

whatis(PROG_NAME .. " version " .. PROG_VERSION)
LmodMessage("load " .. PROG_NAME .. " version " .. PROG_VERSION)

-- Tests of consistency

-- Enviroment variables for NANOS6
setenv("SLURM_CONF" , PROG_HOME .. "/slurm-confdir/slurm.conf")

-- Path
prepend_path("PATH" , PROG_HOME .. "/bin")
prepend_path("PATH" , PROG_HOME .. "/sbin")

prepend_path("C_INCLUDE_PATH" , PROG_HOME .. "/include")
prepend_path("CPLUS_INCLUDE_PATH", PROG_HOME .. "/include")

prepend_path("LD_LIBRARY_PATH" , PROG_HOME .. "/lib")
prepend_path("LD_RUN_PATH" , PROG_HOME .. "/lib")