-- CLE loader. Has no external dependencies.
-- Takes either a file descriptor or a file
-- path as its first argument.

local args = table.pack(...)
local env = {}

-- When running under Cynosure, we get a table of arguments
-- and a table of environment variables. Under Linux, and most
-- other OSes, we'll get a variable number of arguments. This
-- handles both cases.
if type(args[1]) == "table" and type(args[2]) == "table" then
  args, env = args[1], args[2]
end

-- If we're not running under Cynosure, or a similar environment,
-- then create thin wrappers around the io library for open/read/
-- close; otherwise, create thin wrappers around the corresponding
-- system calls.
local open, read, write, close, stderr

-- Cynosure provides a system call, global(), to make certain variables
-- globally available. If that is not present, package.ldcache will be
-- used instead.
local lib_cache

if syscall then
  open = function(path, mode) return syscall("open", path, mode) end
  read = function(fd, format) return syscall("read", fd, format) end
  write = function(fd, ...) return syscall("write", fd, ...) end
  close = function(fd) return syscall("close", fd) end
  exit = function(n) return syscall("exit", n) end
  stderr = 2
  lib_cache = syscall("global", "ld_cache", "table")
else
  open = function(path, mode) return io.open(path, mode) end
  read = function(fd, format) return fd.read(fd, format) end
  write = function(fd, ...) return fd.write(fd, ...) end
  close = function(fd) return fd.close(fd) end
  exit = os.exit
  stderr = io.stderr
  package.ldcache = package.ldcache or {}
  lib_cache = package.ldcache
end

if #args == 0 then
  write(stderr, [[
usage: ld-cle FILE ...

Load and execute a CLE file. Supports both static
and dynamic linking.

Copyright (c) 2022 Ocawesome101 under the GNU
GPLv3.
]])
end

-- If we're passed a file descriptor, then return a function.
-- Otherwise, execute the file directly.
local return_function = true
local fd

if type(args[1]) == "string" then
  return_function = false
  local err
  fd, err = open(args[1], "r")
  if not fd then
    write(stderr, string.format("%s: %s\n", args[1], tostring(err)))
    exit(1)
  end
end

assert(return_function)

local paths = {
  "/lib",
  "/usr/lib"
}

local function search_path(name)
  for _, path in ipairs(paths) do
    local lfd = open(path .. "/" .. name .. ".cs", "r")
    if lfd then return lfd end
  end
  write(stderr, string.format("could not locate shared library %s\n", name))
  exit(2)
end

local function load_library(name)
end
