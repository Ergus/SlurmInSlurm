--
-- Author: Jimmy Aguilar Mena
-- Date: Jul 06, 2022
--

local PROG_NAME = "mympich"
local PROG_VERSION = "personal"
local PROG_HOME = os.getenv("MYMPICH_ROOT")

prereq("myslurm")

if (not PROG_HOME ) then
   LmodError("Environment variable MYMPICH_ROOT is not set" )
end

whatis(PROG_NAME .. " version " .. PROG_VERSION)
LmodMessage("load " .. PROG_NAME .. " version " .. PROG_VERSION)

-- Path
prepend_path("PATH" , PROG_HOME .. "/bin")

prepend_path("C_INCLUDE_PATH" , PROG_HOME .. "/include")
prepend_path("CPLUS_INCLUDE_PATH", PROG_HOME .. "/include")

prepend_path("LD_LIBRARY_PATH" , PROG_HOME .. "/lib")
prepend_path("LIBRARY_PATH" , PROG_HOME .. "/lib")
prepend_path("LD_RUN_PATH" , PROG_HOME .. "/lib")

prepend_path("MANPATH",   PROG_HOME .. "/share/man")
