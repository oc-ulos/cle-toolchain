-- CLE loader. Has no external dependencies.
-- Takes either a file descriptor or a file
-- path as its first argument.

local args = table.pack(...)
local env = {}
local ldcache

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
local open, read, write, close, exit, stderr

-- Cynosure 2 provides the CLE interpreter with a library cache as
-- the second argument, just after the file descriptor. If we're
-- not running under Cynosure 2, we use package.ldcache instead.

if type(args[3]) == "table" then
  local function syscall(...) return coroutine.yield("syscall", ...) end
  open = function(path, mode) return syscall("open", path, mode) end
  read = function(fd, format) return syscall("read", fd, format) end
  write = function(fd, ...) return syscall("write", fd, ...) end
  close = function(fd) return syscall("close", fd) end
  exit = function(n) return syscall("exit", n) end
  stderr = 2
  ldcache = args[2]
else
  open = function(path, mode) return io.open(path, mode) end
  read = function(fd, format) return fd.read(fd, format) end
  write = function(fd, ...) return fd.write(fd, ...) end
  close = function(fd) return fd.close(fd) end
  exit = os.exit
  stderr = io.stderr
  package.ldcache = package.ldcache or {}
  ldcache = package.ldcache
end

if #args == 0 then
  write(stderr, [[
usage: ld-cle FILE ...

Load and execute a dynamically linked CLE file.
Cannot load statically linked CLEs.

Copyright (c) 2022 Ocawesome101 under the GNU
GPLv3.
]])
end

local fd

if type(args[1]) == "string" then
  local err
  fd, err = open(args[1], "r")
  if not fd then
    write(stderr, string.format("%s: %s\n", args[1], tostring(err)))
    exit(1)
  end
else
  fd = args[1]
end

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

local function exec_format_error()
  write(stderr, string.format("exec format error\n"))
  exit(3)
end

local CLE_LUA53   = 0x1
local CLE_EXEC    = 0x2
local CLE_STATIC  = 0x4

local load_cle
local function load_library(name)
  if ldcache[name] then
    return ldcache[name]
  end
  local lfd = search_path(name)
  return load_cle(lfd)()
end

local function read_link(lfd)
  local nlen = read(lfd, 1)
  if nlen then nlen = nlen:byte() else exec_format_error() end

  local name = read(lfd, nlen)
  if not name then exec_format_error() end

  return name
end

local req = require
local function getlink(name)
  return ldcache[name] or (req and req(name))
end

load_cle = function(lfd, mustbeexec)
  local header = read(lfd, 4)
  if header ~= "clex" then
    exec_format_error()
  end

  local flags = read(lfd, 1)
  if flags then flags = flags:byte() else exec_format_error() end

  if mustbeexec and bit32.band(flags, CLE_EXEC) ~= CLE_EXEC then
    exec_format_error()
  end

  local nlink = read(lfd, 1)
  if nlink then nlink = nlink:byte() else exec_format_error() end

  if bit32.band(flags, CLE_STATIC) ~= 0 then
    exec_format_error()
  end

  if bit32.band(flags, CLE_LUA53) == CLE_LUA53 and _VERSION ~= "Lua 5.3" then
    exec_format_error()
  end

  -- Read away the interpreter header.
  read_link(lfd)

  local libs = {}
  for _=1, nlink, 1 do
    local name = read_link(fd)
    libs[#libs+1] = name
    ldcache[name] = load_library(name)
  end

  local data = read(fd, "a")

  close(lfd)

  local ok, err = load(data, "=cle-data", "t", _G)
  if not err then
    write(stderr, err .. "\n")
    exit(3)
  end

  local pargs = {}
  if mustbeexec then
    pargs = table.pack(table.unpack(args, 3))
  end

  local oreq = _G.require
  _G.require = getlink
  local success, result = xpcall(ok, debug.traceback, pargs, env)
  _G.require = oreq
  if not success then
    write(stderr, result .. "\n")
    exit(4)
  end

  return result
end

return load_cle(fd)
