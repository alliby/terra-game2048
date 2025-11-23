local M = {}

M.min =  macro(function(x, y)
  local x_t = x:gettype()
  local y_t = y:gettype()

  assert(x_t:isarithmetic(), "must be a number")
  assert(y_t:isarithmetic(), "must be a number")
  return `terralib.select(x < y, x, y)
end, math.min)

M.max =  macro(function(x, y)
  local x_t = x:gettype()
  local y_t = y:gettype()

  assert(x_t:isarithmetic(), "must be a number")
  assert(y_t:isarithmetic(), "must be a number")

  return `terralib.select(x > y, x, y)
end, math.max)

M.abs = macro(function(v)
  local v_t = v:gettype()
  assert(v_t:isarithmetic(), "must be a number")
  return `terralib.select(v < 0, -v, v)
end, math.abs)

return M
