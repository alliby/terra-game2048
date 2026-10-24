local ffi = require "ffi"

local config = {
  app_name = "2048",
  build_dir = "build",
  deps_dir = "deps",
}

-- Platform detection
-- `terra build.t wasm` builds the web version (requires emsdk, see README)
is_wasm = arg[1] == "wasm"
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

local emsdk = os.getenv("EMSDK")
if is_wasm then
  assert(emsdk, "EMSDK is not set, run `source <path-to-emsdk>/emsdk_env.sh` first")
  config.build_dir = join_paths(config.build_dir, "wasm")
end

local function build_static_lib(name, sources, cflags)
  local cc = is_wasm and "emcc" or "clang"
  local ar = is_wasm and "emar" or "ar"
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
    exec { ar, "rcs", lib_path, obj_list }
    exec { "rm", obj_list }
  end
end

terralib.includepath = table.concat({
    "./deps/nanovg/src",
    "./deps/nanovg/glad/include",
    "./deps/glfw/include",
}, ";")

-- Main build process
if not dir_exists(config.build_dir) then
  exec { "mkdir", (is_windows and "" or "-p"), config.build_dir }
end

-- Build GLAD
if not is_wasm then
  build_static_lib("glad", { "nanovg/glad/src/glad.c" }, { "-I", "deps/nanovg/glad/include" })
end

-- Build NanoVG
local nanovg_implementation
if is_wasm then
  nanovg_implementation = "NANOVG_GLES3_IMPLEMENTATION"
else
  nanovg_implementation = "NANOVG_GL3_IMPLEMENTATION"
end

build_static_lib(
  "nanovg",
  { "nanovg/src/nanovg.c" },
  { "-I", "deps/nanovg/src", "-D_CRT_SECURE_NO_WARNINGS", "-D" .. nanovg_implementation }
)

-- Build GLFW
if not is_wasm then
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
end

-- Build Terra application
local start = os.clock()

local target -- nil means native
if is_wasm then
  -- Terra's LLVM can emit wasm32 objects, but on x86 hosts it rewrites CPU "generic"
  -- to "x86-64" whatever the triple is, so a wasm-specific CPU name has to be used.
  -- Features must stay empty: Terra hands them to clang as a single -target-feature.
  target = terralib.newtarget {
    Triple = "wasm32-unknown-emscripten",
    CPU = "mvp",
    Features = "",
  }

  -- Parse C headers against the emscripten sysroot (same search order as emcc)
  -- instead of the host libc, so types like `long` and `size_t` match wasm32.
  local sysroot = join_paths(emsdk, "upstream", "emscripten", "cache", "sysroot")
  local cargs = {
    "-internal-isystem", join_paths(sysroot, "include", "compat"),
    "-internal-isystem", "$CLANG_RESOURCE$/include",
    "-internal-isystem", join_paths(sysroot, "include"),
  }

  C = terralib.includecstring([[
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <time.h>
    #include <emscripten.h>
    #include <GLES3/gl3.h>
    #include <GLFW/glfw3.h>
    #define NANOVG_GLES3_IMPLEMENTATION
    #include "nanovg.h"
    #include "nanovg_gl.h"
  ]], cargs, target)
else
  C = terralib.includecstring(string.format([[
    #include "stdio.h"
    #include "time.h"
    #define _CRT_SECURE_NO_WARNINGS
    #define %s
    #include "glad/glad.h"
    #include "GLFW/glfw3.h"
    #include "nanovg.h"
    #include "nanovg_gl.h"
  ]], nanovg_implementation))
end

local main_fn = require "main"

-- Link final executable
local output, link_flags, entry_point

if is_wasm then
  local obj = join_paths(config.build_dir, config.app_name .. ".o")
  terralib.saveobj(obj, { main = main_fn }, nil, target)

  -- Let emscripten link the object: it provides libc, GLFW and GLES3 (WebGL 2)
  exec { "mkdir", "-p", "web" }
  exec {
    "emcc", obj, join_paths(config.build_dir, "libnanovg.a"),
    "-O2", "-sUSE_GLFW=3", "-sMIN_WEBGL_VERSION=2", "-sMAX_WEBGL_VERSION=2",
    "-sALLOW_MEMORY_GROWTH", "--shell-file", "shell.html",
    "-o", "web/index.html"
  }
  print(string.format("\n=== Build completed in %.2f seconds ===\n", os.clock() - start))
  return
elseif is_windows then
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
    "-lm"
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
