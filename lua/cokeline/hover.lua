local M = {}

local version = vim.version()

local buffers = require("cokeline.buffers")
local rendering = require("cokeline.rendering")
local last_position = nil

function M.hovered()
  return _G.cokeline.__hovered
end

function M.get_current(col)
  local bufs = buffers.get_visible()
  if not bufs then
    return
  end
  local cx = rendering.prepare(bufs)

  local current_width = 0
  for _, component in ipairs(cx.sidebar) do
    current_width = current_width + component.width
    if current_width >= col then
      return component
    end
  end
  for _, component in ipairs(cx.buffers) do
    current_width = current_width + component.width
    if current_width >= col then
      return component
    end
  end
  current_width = current_width + cx.gap
  if current_width >= col then
    return
  end
  for _, component in ipairs(cx.rhs) do
    current_width = current_width + component.width
    if current_width >= col then
      return component
    end
  end
end

local function on_hover(current)
  local hovered = _G.cokeline.__hovered
  if vim.o.showtabline == 0 then
    return
  end
  if current.screenrow == 1 then
    if
      last_position
      and hovered
      and last_position.screencol == current.screencol
    then
      return
    end
    local component = M.get_current(current.screencol)

    if
      component
      and hovered
      and component.index == hovered.index
      and component.bufnr == hovered.bufnr
    then
      return
    end

    if hovered ~= nil then
      local buf = buffers.get_buffer(hovered.bufnr)
      if buf then
        buf.is_hovered = false
      end
      if hovered.on_mouse_leave then
        if hovered.kind == "buffer" then
          if buf ~= nil then
            hovered.on_mouse_leave(buf)
          end
        else
          hovered.on_mouse_leave(buf)
        end
      end
      _G.cokeline.__hovered = nil
    end
    if not component then
      vim.cmd.redrawtabline()
      return
    end

    local buf = buffers.get_buffer(component.bufnr)
    if buf then
      buf.is_hovered = true
    end
    if component.on_mouse_enter then
      if component.kind == "buffer" then
        if buf ~= nil then
          component.on_mouse_enter(buf, current.screencol)
        end
      else
        component.on_mouse_enter(buf, current.screencol)
      end
    end
    _G.cokeline.__hovered = {
      index = component.index,
      bufnr = buf and buf.number or nil,
      on_mouse_leave = component.on_mouse_leave,
      kind = component.kind,
    }
    vim.cmd.redrawtabline()
  elseif hovered ~= nil then
    local buf = buffers.get_buffer(hovered.bufnr)
    if buf then
      buf.is_hovered = false
    end
    if hovered.on_mouse_leave then
      if hovered.kind == "buffer" then
        if buf ~= nil then
          hovered.on_mouse_leave(buf)
        end
      else
        hovered.on_mouse_leave(buf)
      end
    end
    _G.cokeline.__hovered = nil
    vim.cmd.redrawtabline()
  end
  last_position = current
end

function M.setup()
  if version.minor < 8 then
    return
  end

  vim.api.nvim_create_autocmd("MouseMoved", {
    callback = function(ev)
      on_hover(ev.data)
      return "<MouseMove>"
    end,
  })
end

return M
