struct Vector2 {
  x: float,
  y: float,
}  

struct Rect {
  x: float,
  y: float,
  w: float,
  h: float
}

local Color = {uint8, uint8, uint8}

local GAME_BACKGROUND_COLOR = `{ 187, 173, 160 }
local TILE_BACKGROUND_COLOR = `{ 205, 193, 180 }
local TEXT_COLOR = `{ 120, 110, 101 }

local OFFSET = 20
local GAME_RECT_SIZE = WINDOW_WIDTH - 2 * OFFSET
local GAME_RECT = `Rect { OFFSET, OFFSET + WINDOW_HEIGHT - WINDOW_WIDTH, GAME_RECT_SIZE, GAME_RECT_SIZE }
local TITLE_RECT = `Rect { GAME_RECT.x, OFFSET, GAME_RECT_SIZE, 100 }
local SCORE_RECT = `Rect { GAME_RECT.x, TITLE_RECT.y + 120, GAME_RECT_SIZE, 60 }
local RETRY_BTN_RECT = `Rect { GAME_RECT.x, SCORE_RECT.y, 100, 60 }

local TILE_COUNT = 4
local GAP = 10
local TILE_SIZE = (GAME_RECT_SIZE - (TILE_COUNT+1) * GAP) / TILE_COUNT
local TILE_COLORS = {
  [2] = `{238, 228, 218},
  [4] = `{237, 224, 200},
  [8] = `{242, 177, 121},
  [16] = `{245, 149, 99},
  [32] = `{246, 124, 95},
  [64] = `{246, 94, 59},
  [128] = `{237, 207, 114},
  [256] = `{237, 204, 97},
  [512] = `{237, 200, 80},
  [1024] = `{253, 190, 23},
}

local TITLE_FONT_SIZE = 120
local TILE_FONT_SIZE = 70

terra getRandomInt(min: int, max: int)
  C.srand(C.glfwGetTime())
  return (C.rand() % (max + 1) - min) + min
end

terra intToString(num: int)
  var buffer : int8[10]
  C.sprintf(buffer, "%d", num)
 return buffer
end

terra tileColor(level: int): Color
  escape for l,c in pairs(TILE_COLORS) do
    emit quote if l == level then return c end end
  end end
  -- Fallback Color
  return { 253, 190, 93 }
end

terra tileTextColor(level: int): Color
  if level <= 4 then
    return { 119, 110, 101 }
  else
    return { 245, 245, 245 }
  end
end

terra drawRect(vg: &C.NVGcontext, rect: Rect, color: Color)
  var x, y, w, h = unpackstruct(rect)
  C.nvgBeginPath(vg)
  C.nvgFillColor(vg, C.nvgRGB(unpacktuple(color)))
  C.nvgRect(vg, x, y, w, h)
  C.nvgFill(vg)
end

terra drawRectRounded(vg: &C.NVGcontext, rect: Rect, color: Color)
  var x, y, w, h = unpackstruct(rect)
  C.nvgBeginPath(vg)
  C.nvgFillColor(vg, C.nvgRGB( unpacktuple(color) ))
  C.nvgRoundedRect(vg, x, y, w, h, 10.0)
  C.nvgFill(vg)
end

-- Draw text, center it and clip it if out of rectangle 
terra drawText(vg: &C.NVGcontext, text: rawstring, size: float, bounds: Rect, color: Color)
  C.nvgSave(vg)
  defer C.nvgRestore(vg)
  
  var x, y, w, h = unpackstruct(bounds)
  -- Scissoring
  C.nvgScissor(vg, x , y, w, h)
  defer C.nvgResetScissor(vg)
  -- Some text configuration
  C.nvgFontSize(vg, size)
  C.nvgFontFace(vg, "default")
  C.nvgTextAlign(vg, [ bit.bor(C.NVG_ALIGN_LEFT, C.NVG_ALIGN_MIDDLE) ]);
  C.nvgFillColor(vg, C.nvgRGB(unpacktuple(color)))
  var text_bounds: float[4]
  C.nvgTextBounds(vg, x, y, text, nil, [&float](text_bounds))
  var text_width = text_bounds[2] - text_bounds[0]
  -- Centering
  var text_x = math.max(x, x + (w - text_width) / 2)
  var text_y = y + h / 2
  C.nvgText(vg, text_x, text_y, text, nil)
end

terra drawScore(vg: &C.NVGcontext, score: uint, bounds: Rect)
  var buffer : int8[20]
  C.sprintf(buffer, "score: %d", score)
  drawText(vg, buffer, 70, bounds, { 70, 60, 70 })
end

terra checkCollision(rect: Rect): bool
  return (CURSOR_X >= rect.x and CURSOR_X <= (rect.x + rect.w))
    and (CURSOR_Y >= rect.y and CURSOR_Y <= (rect.y + rect.h))
end

terra drawRetryButton(vg: &C.NVGcontext, bounds: Rect): bool
  if checkCollision(bounds) then
    drawRectRounded(vg, bounds, { 50, 40, 80 })
  else
    drawRectRounded(vg, bounds, { 20, 20, 20 })
  end
  drawText(vg, "Retry", 45, bounds, { 220, 220, 220 })
  return checkCollision(bounds) and IS_MOUSE_PRESSED
end

terra tilePosition(i: int, j: int): { float, float }
  return GAME_RECT.x + GAP + i * (TILE_SIZE + GAP),
    GAME_RECT.y + GAP + j * (TILE_SIZE + GAP)
end

terra drawTilesGrid(vg: &C.NVGcontext)
  for idx=0,TILE_COUNT*TILE_COUNT do
    var i = idx / TILE_COUNT
    var j = idx % TILE_COUNT
    var x, y = tilePosition(i, j)
    drawRectRounded(vg, Rect { x, y, TILE_SIZE, TILE_SIZE }, TILE_BACKGROUND_COLOR)
  end
end

terra drawTileXY(vg: &C.NVGcontext, x: float, y: float, level: int)
  var rect = Rect { x, y, TILE_SIZE, TILE_SIZE }
  drawRectRounded(vg, rect, tileColor(level))
  var str = intToString(level)
  drawText(vg, str, TILE_FONT_SIZE, rect, tileTextColor(level))
end

terra drawTileScale(vg: &C.NVGcontext, x: float, y: float, scale: float, level: int)
  var scaled_size = TILE_SIZE * scale
  var scaled_x = x + (TILE_SIZE - scaled_size) / 2
  var scaled_y = y + (TILE_SIZE - scaled_size) / 2
  var rect = Rect { scaled_x, scaled_y, scaled_size, scaled_size }
  drawRectRounded(vg, rect, tileColor(level))
  var str = intToString(level)
  drawText(vg, str, TILE_FONT_SIZE * scale, rect, tileTextColor(level))
end

terra drawAnimation(vg: &C.NVGcontext, i: int, j: int, animation: Animation, level: int)
  var x,y = tilePosition(i, j)
  if animation.dir[0] == 0 and animation.dir[1] == 0 then
    drawTileScale(vg, x, y, animation.prog, level)
  else
    if animation.dir[0] == 1 or animation.dir[0] == -1 then
      drawTileXY(vg, animation.prog, y, level)
    end
    if animation.dir[1] == 1 or animation.dir[1] == -1 then
      drawTileXY(vg, x, animation.prog, level)
    end
  end
end

terra drawTile(vg: &C.NVGcontext, i: int, j: int, level: int)
  var x,y = tilePosition(i, j)
  drawTileXY(vg, x, y, level)
end

struct Animation {
  started: bool,
  dir: int8[2],
  start: float,
  dest: float,
  prog: float,
}

Animation.methods.new = terra(idx1: int, idx2: int, dir: int8[2])
  -- Scale Animation (no direction needed)
  if dir[0] == 0 and dir[1] == 0 then
    return Animation { false, dir, 0.0, 1.0, 0.0 }
  end

  -- Slide Animation
  var start: float, dest: float
  var start_x, start_y = tilePosition(idx1 % TILE_COUNT, idx1 / TILE_COUNT)
  var dest_x, dest_y = tilePosition(idx2 % TILE_COUNT, idx2 / TILE_COUNT)
  
  if dir[1] ~= 0 then
    start = start_y
    dest = dest_y
  else
    start = start_x
    dest = dest_x
  end

  return Animation { false, dir, start, dest, start }
end

terra Animation:is_finished()
  return self.prog == self.dest
end

terra Animation:update(step: float)
  if not self.started then return end

  -- Scale Update
  if self.dir[0] == 0 and self.dir[1] == 0 then
    self.prog = math.min(self.prog + (step / 200), 1.0)
  end

  -- Slide Update
  if self.dir[0] == 1 or self.dir[1] == 1 then
    self.prog = math.min(self.prog + step, self.dest)
  end

  if self.dir[0] == -1 or self.dir[1] == -1 then
    self.prog = math.max(self.prog - step, self.dest)
  end
    
  if self:is_finished() then
    self.started = false
  end
end

terra getColumn(arr: &int, n: int)
  var column: int[TILE_COUNT]
  for i=0,TILE_COUNT do
    column[i] = arr[i + TILE_COUNT*n]
  end
  return column
end

terra getRow(arr: &int, n: int)
  var row: int[TILE_COUNT]
  for i=0,TILE_COUNT do
    row[i] = arr[i*TILE_COUNT + n]
  end
  return row
end

terra setColumn(arr: &int, column: int[TILE_COUNT], n: int)
  for i=0,TILE_COUNT do
    arr[i + TILE_COUNT*n] = column[i]
  end
end

terra setRow(arr: &int, row: int[TILE_COUNT], n: int)
  for i=0,TILE_COUNT do
    arr[i*TILE_COUNT + n] = row[i]
  end
end

terra processLine(arr: &int, animations: &Animation, n: int, mov: int8[2]): uint
  var line: int[TILE_COUNT]
  var dir: int
  var score = 0
  
  if mov[0] ~= 0 then
    line = getColumn(arr, n)
    dir = mov[0]
  end

  if mov[1] ~= 0 then
    line = getRow(arr, n)
    dir = mov[1]
  end
  
  var idx: int
  var inc: int
  var endd: int

  -- Right or Up
  if dir == 1 then
    idx = TILE_COUNT - 1
    inc = -1
    endd = -1
  end

  -- Left or Down
  if dir == -1 then
    idx = 0
    inc = 1
    endd = TILE_COUNT
  end
  
  var current = line[idx]

  while true do
    var old_idx = idx
    var new_idx = idx

    if current == 0 then
      for i=idx + inc, endd, inc do
	if line[i] ~= 0 then
	  current = line[i]
	  old_idx = i
	  new_idx = idx
	  line[new_idx] = line[old_idx]
	  line[old_idx] = 0
	  goto out
	end
      end
    end

    for i=idx + inc, endd, inc do
      if current ~= line[i] and line[i] ~= 0 then
	current = line[i]
	idx = idx + inc
	old_idx = i
	new_idx = idx
	line[old_idx] = 0
	line[new_idx] = current
	goto out
      elseif current == line[i] then -- Merge is happening
	line[idx] = current * 2
	score = score + line[idx] -- append to score
	idx = idx + inc
	
	old_idx = i
	new_idx = idx
	current = 0
	line[old_idx] = 0
	goto out
      end
    end

    break

    ::out::
    if mov[0] ~= 0 then
      old_idx = n*TILE_COUNT + old_idx
      new_idx = n*TILE_COUNT + new_idx
    end

    if mov[1] ~= 0 then
      old_idx = old_idx*TILE_COUNT + n
      new_idx = new_idx*TILE_COUNT + n
    end

    animations[new_idx] = Animation.new(old_idx, new_idx, mov)
    animations[new_idx].started = true
  end

  if mov[0] ~= 0 then
    setColumn(arr, line, n)
  end

  if mov[1] ~= 0 then
    setRow(arr, line, n)
  end

  return score
end

terra spawnTiles(tiles: &int, animations: &Animation)
  var zero_tiles_indices: int[TILE_COUNT * TILE_COUNT]
  C.memset(&zero_tiles_indices, 0, sizeof( [zero_tiles_indices.type] ))
  var idx = 0
  for i=0,TILE_COUNT*TILE_COUNT do
    if tiles[i] == 0 then
      zero_tiles_indices[idx] = i
      idx = idx + 1
    end
  end
  if idx == 0 then return end
  var rand = getRandomInt(0, idx-1)
  var tile_idx = zero_tiles_indices[rand]
  tiles[tile_idx] = 2

  animations[tile_idx] = Animation.new(tile_idx, tile_idx, arrayof(int8, 0, 0))
  animations[tile_idx].started = true
end

struct GameState {
  tiles: int[TILE_COUNT*TILE_COUNT],
  animations: Animation[TILE_COUNT*TILE_COUNT],
  score: uint
}

GameState.methods.new = terra()
  var state = GameState { }
  C.memset(&state, 0, sizeof( [ state.type ] ))

  -- The first two tiles
  var idx1 = getRandomInt(0, TILE_COUNT)
  var idx2 = getRandomInt(TILE_COUNT+1, TILE_COUNT * TILE_COUNT - 1)
  state.tiles[idx1] = 2
  state.tiles[idx2] = 2
  return state
end

terra updateState(state: &GameState, mov: int8[2], delta: float)
  if mov[0] ~= 0 or mov[1] ~= 0 then
    for i=0,TILE_COUNT do
      var score = processLine(state.tiles, state.animations, i, mov)
      state.score = state.score + score
    end
    spawnTiles(state.tiles, state.animations)
  end

  for i=0,TILE_COUNT*TILE_COUNT do
    state.animations[i]:update(delta)
  end
end

terra draw(vg: &C.NVGcontext, state: &GameState, dt: double)
  C.nvgSave(vg)
  defer C.nvgRestore(vg)

  -- Setup
  drawText(vg, "2048", TITLE_FONT_SIZE, TITLE_RECT, TEXT_COLOR)
  drawRectRounded(vg, GAME_RECT, GAME_BACKGROUND_COLOR)
  drawTilesGrid(vg)
  
  -- mouvements
  var mov = arrayof(int8, 0, 0)
  
  if PRESSED_KEY == C.GLFW_KEY_RIGHT then
    mov[0] = 1
  end

  if PRESSED_KEY == C.GLFW_KEY_LEFT then
    mov[0] = -1
  end

  if PRESSED_KEY == C.GLFW_KEY_UP then
    mov[1] = -1
  end

  if PRESSED_KEY == C.GLFW_KEY_DOWN then
    mov[1] = 1
  end

  -- draw retry button
  if drawRetryButton(vg, RETRY_BTN_RECT) then
    @state = GameState.new()
  end
  
  -- update
  updateState(state, mov, dt * 1000 * 2)

  -- draw Score
  drawScore(vg, state.score, SCORE_RECT)
  
  -- draw Tiles
  for idx=0,TILE_COUNT*TILE_COUNT do
    var animation = state.animations[idx]
    var tile = state.tiles[idx]
    if tile == 0 then goto continue end
    var i = idx % TILE_COUNT
    var j = idx / TILE_COUNT
    if animation.started then
      drawAnimation(vg, i, j, animation, tile)
    else
      drawTile(vg, i, j, tile)
    end
    ::continue::
  end

end
