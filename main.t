-- All C.* calls are located in "build.t"
local memset = C.memset
local printf = C.printf
local perror = C.perror

-- Global variables
WINDOW_HEIGHT = 800
WINDOW_WIDTH = 600
BACKGROUND_COLOR = { 0.9, 0.9, 0.9, 1.0 }
FONT_PATH = "fonts/SmoochSans-Bold.ttf"
local font_file = io.open(FONT_PATH, "rb")
FONT_BYTES = font_file:read("*all")
font_file:close()

PRESSED_KEY = global(int)
CURSOR_X = global(double)
CURSOR_Y = global(double)
IS_MOUSE_PRESSED = global(bool, false)

-- GLFW callbacks
local terra error_callback(error: int, desc: rawstring)
   perror("GLFW ERROR")
end

local terra key_callback(window: &C.GLFWwindow, key: int, scancode: int, action: int, mods: int)
  if action == C.GLFW_PRESS then
    PRESSED_KEY = key
  end

  if key == C.GLFW_KEY_Q and action == C.GLFW_RELEASE then
      C.glfwSetWindowShouldClose(window, C.GL_TRUE)
  end
end

local terra cursor_pos_callback(window: &C.GLFWwindow, xpos: double, ypos: double)
  CURSOR_X = xpos
  CURSOR_Y = ypos
end

local terra mouse_button_callback(window: &C.GLFWwindow, button: int, action: int, mods: int)
  IS_MOUSE_PRESSED = (button == C.GLFW_MOUSE_BUTTON_1 and action == C.GLFW_PRESS)
end

math = require "./math"
require "game"

terra main()
  -- initialize GLFW
  if C.glfwInit() == 0 then
    perror("Error: Failed to initialize GLFW\n")
    return -1
  end
  defer C.glfwTerminate()

  C.glfwWindowHint(C.GLFW_RESIZABLE, C.GL_FALSE)
  C.glfwWindowHint(C.GLFW_CONTEXT_VERSION_MAJOR, 3)
  C.glfwWindowHint(C.GLFW_CONTEXT_VERSION_MINOR, 2)
  C.glfwWindowHint(C.GLFW_OPENGL_FORWARD_COMPAT, C.GL_TRUE)
  C.glfwWindowHint(C.GLFW_OPENGL_PROFILE, C.GLFW_OPENGL_CORE_PROFILE)

  -- Create GLFW Window
  var window = C.glfwCreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "2048", nil, nil)
  if window == nil then
    perror("Error: Failed to Create GLFW window\n")
    return -1
  end
  defer C.glfwDestroyWindow(window)

  -- Enable VSYNC
  C.glfwMakeContextCurrent(window)
  C.glfwSwapInterval(1)

  -- Set GLFW callbacks
  C.glfwSetErrorCallback(error_callback)
  C.glfwSetKeyCallback(window, key_callback)
  C.glfwSetCursorPosCallback(window, cursor_pos_callback)
  C.glfwSetMouseButtonCallback(window, mouse_button_callback)

  -- load gl function pointers with glad
  if C.gladLoadGLLoader([C.GLADloadproc](C.glfwGetProcAddress)) == 0 then
    perror("ERROR: Could not load glad loader\n")
    return -1
  end

  -- Create NanoVG Context
  var vg = C.nvgCreateGL3([bit.bor(C.NVG_STENCIL_STROKES, C.NVG_DEBUG , C.NVG_ANTIALIAS)])
  if vg == nil then
    perror("ERROR: Failed to create NANOVG context\n")
    return -1
  end
  defer C.nvgDeleteGL3(vg)

  -- Add font to NanoVG
  var font = C.nvgCreateFontMem(vg, "default", [&uint8]([FONT_BYTES]), [#FONT_BYTES], 0)

  var state = GameState.new()
  var t = C.glfwGetTime()
  while not [bool](C.glfwWindowShouldClose(window)) do
    var new_t = C.glfwGetTime()
    var dt = new_t - t
    t = new_t

    C.glad_glViewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
    C.glad_glClearColor(BACKGROUND_COLOR)
    C.glad_glClear(C.GL_COLOR_BUFFER_BIT or C.GL_DEPTH_BUFFER_BIT or C.GL_STENCIL_BUFFER_BIT)
    C.nvgBeginFrame(vg, WINDOW_WIDTH, WINDOW_HEIGHT, 1.0)

    defer C.glfwSwapBuffers(window)
    defer C.glfwPollEvents()
    defer C.nvgEndFrame(vg)

    draw(vg, &state, dt)

    -- reset keys and mouse button
    PRESSED_KEY = 0
    IS_MOUSE_PRESSED = false

  end

  return 0
end

return main
