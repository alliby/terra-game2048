local ffi = require "ffi"

local config = {
  app_name = "2048",
  build_dir = "build",
  deps_dir = "deps",
}

-- Platform detection
local is_windows = ffi.os == "Windows"
local is_linux = ffi.os == "Linux"
local is_macos = ffi.os == "OSX"

-- Helper functions
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local dir_exists = file_exists
if is_windows then
  ffi.cdef [[
    typedef unsigned long DWORD;
    typedef const char* LPCSTR;

    static const DWORD INVALID_FILE = 0xFFFFFFFF;
    static const DWORD FILE_ATTRIBUTE_DIRECTOTY = 0x00000010;

    DWORD GetFileAttributesA(LPCSTR tpFileName);
  ]]

  dir_exists = function(path)
    local attr = ffi.C.GetFileAttributesA(path)
    if attr == ffi.C.INVALID_FILE then return false end
    return bit.band(attr, ffi.C.FILE_ATTRIBUTE_DIRECTOTY)
  end
end

local function exec(...)
  local cmd = table.concat(..., " ")
  print("[CMD] " .. cmd)
  local result = os.execute(cmd)
  if result ~= 0 and result ~= true then
    error("Command failed: " .. cmd)
  end
end

local function join_paths(...)
  local sep = is_windows and "\\" or "/"
  return table.concat({...}, sep)
end

local function build_static_lib(name, sources, cflags)
  local cc = "clang"
  local lib_name = is_windows and (name .. ".lib") or ("lib" .. name .. ".a")
  local lib_path = join_paths(config.build_dir, lib_name)
  if file_exists(lib_path) then return end

  -- Compile sources
  local objects = {}
  for _, src in ipairs(sources) do
    local obj_name = src:match("([^/\\]+)%.c$") .. ( is_windows and ".obj" or ".o")
    local obj_path = is_windows and obj_name or join_paths(config.build_dir, obj_name)
    local src = join_paths(config.deps_dir, src)
    table.insert(objects, obj_path)

    if not file_exists(obj_path) then
      exec { cc, "-c", src, table.concat(cflags, " "), "-o", obj_path }
    end
  end

  -- Create static library
  if is_windows then
    local obj_list = table.concat(objects, " ")
    exec { "llvm-lib", "/OUT:" .. lib_path, obj_list }
    exec { "del", obj_list }
  else
    local obj_list = table.concat(objects, " ")
    exec { "ar", "rcs", lib_path, obj_list }
    exec { "rm", obj_list }
  end
end

-- Main build process
if not dir_exists(config.build_dir) then
  exec { "mkdir ", (is_windows and "" or "-p "), config.build_dir }
end

-- Build GLAD
build_static_lib("glad", { "nanovg/glad/src/glad.c" }, { "-I", "deps/nanovg/glad/include" })

-- Build NanoVG
build_static_lib("nanovg", { "nanovg/src/nanovg.c" },
		 { "-I", "deps/nanovg/src", "-D_CRT_SECURE_NO_WARNINGS", "-DNANOVG_GL3_IMPLEMENTATION" })

-- Build GLFW
local glfw_sources = {
  "glfw/src/context.c", "glfw/src/egl_context.c", "glfw/src/init.c",
  "glfw/src/input.c", "glfw/src/monitor.c", "glfw/src/null_init.c",
  "glfw/src/null_joystick.c", "glfw/src/null_monitor.c",
  "glfw/src/null_window.c", "glfw/src/osmesa_context.c",
  "glfw/src/platform.c", "glfw/src/vulkan.c", "glfw/src/window.c"
}

if is_windows then
  local win_sources = {
    "glfw/src/wgl_context.c", "glfw/src/win32_init.c",
    "glfw/src/win32_joystick.c", "glfw/src/win32_module.c",
    "glfw/src/win32_monitor.c", "glfw/src/win32_thread.c",
    "glfw/src/win32_time.c", "glfw/src/win32_window.c"
  }
  for _, src in ipairs(win_sources) do
    table.insert(glfw_sources, src)
  end
  build_static_lib("glfw", glfw_sources, { "-D_GLFW_WIN32" })
else
  local linux_sources = {
    "glfw/src/linux_joystick.c", "glfw/src/posix_module.c",
    "glfw/src/posix_poll.c", "glfw/src/posix_thread.c",
    "glfw/src/posix_time.c", "glfw/src/xkb_unicode.c",
    "glfw/src/glx_context.c", "glfw/src/x11_init.c",
    "glfw/src/x11_monitor.c", "glfw/src/x11_window.c"
  }
  for _, src in ipairs(linux_sources) do
    table.insert(glfw_sources, src)
  end
  build_static_lib("glfw", glfw_sources, { "-D_GLFW_X11", "-I", "deps/x11-headers" })
end

-- Build Terra application
local start = os.clock()

terralib.includepath = table.concat({
    "./deps/nanovg/src",
    "./deps/nanovg/glad/include",
    "./deps/glfw/include"
}, ";")

C = terralib.includecstring [[
  #include "stdio.h"
  #include "time.h"
  #define _CRT_SECURE_NO_WARNINGS
  #define NANOVG_GL3_IMPLEMENTATION
  #include "glad/glad.h"
  #include "GLFW/glfw3.h"
  #include "nanovg.h"
  #include "nanovg_gl.h"
]]

local main_fn = require "main"

-- Link final executable
local output, link_flags, entry_point

if is_windows then
  output = config.app_name .. ".exe"
  entry_point = "WinMain"
  link_flags = {
    "build\\glad.lib", "build\\glfw.lib", "build\\nanovg.lib",
    "gdi32.lib", "opengl32.lib", "shell32.lib", "user32.lib",
    "-NODEFAULTLIB:LIBCMT"
  }
elseif is_linux then
  output = "./" .. config.app_name
  entry_point = "main"
  link_flags = {
    "-Lbuild", "-l:libglad.a", "-l:libglfw.a", "-l:libnanovg.a",
    "-lm", "-s"
  }
else -- macOS
  output = "./" .. config.app_name
  entry_point = "main"
  link_flags = {
    "-Lbuild", "-lglad", "-lglfw", "-lnanovg",
    "-framework", "Cocoa", "-framework", "OpenGL",
    "-framework", "IOKit", "-framework", "CoreVideo", "-lm"
  }
end

terralib.saveobj(output, { [entry_point] = main_fn }, link_flags)
print(string.format("\n=== Build completed in %.2f seconds ===\n", os.clock() - start))

-- Run the application
exec { output }
