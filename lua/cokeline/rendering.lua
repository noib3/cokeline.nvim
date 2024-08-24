local lazy = require("cokeline.lazy")
local state = lazy("cokeline.state")
local config = lazy("cokeline.config")
local components = lazy("cokeline.components")
local sidebar = lazy("cokeline.sidebar")
local rhs = lazy("cokeline.rhs")
local tabs = lazy("cokeline.tabs")
local RenderContext = lazy("cokeline.context")
local iter = require("plenary.iterators").iter

local insert = table.insert
local sort = table.sort
local unpack = unpack or table.unpack

local extend = vim.list_extend
local o = vim.o

---@type index
local current_index

---@param buffers  Buffer[]
---@param previous_buffer_index  index
---@return Buffer
local find_current_buffer = function(buffers, previous_buffer_index)
  local focused_buffer = iter(buffers):find(function(buffer)
    return buffer.is_focused
  end)

  return focused_buffer or buffers[previous_buffer_index] or buffers[#buffers]
end

---@param c1  Component
---@param c2  Component
---@return boolean
local by_decreasing_priority = function(c1, c2)
  return c1.truncation.priority < c2.truncation.priority
end

---@param c1  Component
---@param c2  Component
---@return boolean
local by_increasing_index = function(c1, c2)
  return c1.index < c2.index
end

-- Takes in either a single buffer or a list of buffers, and it returns a list
-- of all the rendered components together with their total combined width.
---@param context Buffer|Buffer[]|TabPage|TabPage[]
---@param complist Component[]
---@return Component, number
local function to_components(context, complist)
  local hovered = require("cokeline.hover").hovered()
  -- A simple heuristic to check if we're dealing with single buffer or a list
  -- of them is to just check if one of they keys is defined.
  if context.number then
    local cs = {}
    for _, c in ipairs(complist) do
      local render_cx
      if context.filetype then
        render_cx = RenderContext:buffer(context)
        render_cx.provider.buf_hovered = hovered ~= nil
          and hovered.bufnr == context.number
      else
        render_cx = RenderContext:tab(context)
        render_cx.provider.tab_hovered = hovered ~= nil
          and hovered.bufnr == context.number
      end
      render_cx.provider.is_hovered = hovered ~= nil
        and hovered.bufnr == context.number
        and hovered.index == c.index
      local rendered = c:render(render_cx)
      render_cx.provider.is_hovered = false
      if rendered.width > 0 then
        insert(cs, rendered)
      end
    end

    local width = components.width(cs)
    if width <= config.rendering.max_buffer_width then
      return cs, width
    else
      sort(cs, by_decreasing_priority)
      components.shorten(cs, config.rendering.max_buffer_width)
      sort(cs, by_increasing_index)
      return cs, config.rendering.max_buffer_width
    end
  else
    local cs = {}
    local width = 0
    for _, buffer in ipairs(context) do
      local buf_components, buf_width = to_components(buffer, complist)
      width = width + buf_width
      for _, component in pairs(buf_components) do
        insert(cs, component)
      end
    end
    return cs, width
  end
end

---This is a helper function for rendering and hover handers. It takes
---the list of visible buffers, figures out which components to display, and
---returns a list of pre-render components
---@param visible_buffers  Buffer[]
---@return table|string
local prepare = function(visible_buffers)
  local sidebar_components_l = sidebar.get_components("left")
  local sidebar_components_r = sidebar.get_components("right")
  local rhs_components = rhs.get_components()
  local available_width = o.columns - components.width(sidebar_components_l)
  if available_width == 0 then
    return components.render(sidebar_components_l)
  end

  local tab_placement
  local tab_components
  local tabs_width
  if config.tabs then
    tab_placement = config.tabs.placement or "left"
    tab_components = to_components(tabs.get_tabs(), state.tabs)
    tabs_width = components.width(tab_components)
    available_width = available_width - tabs_width
    if available_width == 0 then
      return components.render(sidebar_components_l)
        .. components.render(tab_components)
    end
  end

  local current_buffer = find_current_buffer(visible_buffers, current_index)

  local current_components, current_width
  if current_buffer then
    current_index = current_buffer.index

    current_components, current_width =
      to_components(current_buffer, state.components)
    if current_width >= available_width then
      sort(current_components, by_decreasing_priority)
      components.shorten(current_components, available_width)
      sort(current_components, by_increasing_index)
      if current_buffer.index > 1 then
        components.shorten(current_components, available_width, "left")
      end
      if current_buffer.index < #visible_buffers then
        components.shorten(current_components, available_width, "right")
      end

      return {
        sidebar_left = sidebar_components_l,
        sidebar_right = sidebar_components_r,
        buffers = current_components,
        rhs = rhs_components,
        tabs = tab_components,
        gap = math.max(
          0,
          available_width
            - (
              components.width(current_components)
              + components.width(rhs_components)
            )
        ),
      }
    end
  else
    current_components, current_width = {}, 0
  end

  local left_components, left_width
  local right_components, right_width
  if #visible_buffers > 0 then
    left_components, left_width = to_components({
      unpack(visible_buffers, 1, current_buffer.index - 1),
    }, state.components)

    right_components, right_width = to_components({
      unpack(visible_buffers, current_buffer.index + 1, #visible_buffers),
    }, state.components)
  else
    left_components, left_width = {}, 0
    right_components, right_width = {}, 0
  end

  local rhs_width = components.width(rhs_components)
    + components.width(sidebar_components_r)
  local available_width_left, available_width_right = config.rendering.slider(
    available_width
      - current_width
      - rhs_width
      - ((tabs_width ~= nil and tab_placement == "right") and tabs_width or 0),
    left_width,
    right_width
  )

  -- If we handled left, current and right components separately we might have
  -- to shorten the left or right components with a `to_width` parameter of 1,
  -- in which case the correct behaviour would be to "shorten" the current
  -- buffer components instead.
  --
  -- To avoid this, we join all the buffer components together *before*
  -- checking if they need to be shortened.
  local buffer_components =
    extend(extend(left_components, current_components), right_components)

  if left_width > available_width_left then
    components.shorten(
      buffer_components,
      available_width - rhs_width,
      -- available_width_left + current_width + right_width + rhs_width,
      "left"
    )
  end
  if right_width > available_width_right then
    components.shorten(buffer_components, available_width - rhs_width, "right")
  end

  local bufs_width = components.width(buffer_components)
  return {
    sidebar_left = sidebar_components_l,
    sidebar_right = sidebar_components_r,
    buffers = buffer_components,
    rhs = rhs_components,
    tabs = tab_components,
    gap = math.max(0, available_width - (bufs_width + rhs_width)),
  }
end

---This is the main function responsible for rendering the bufferline. It takes
---the list of visible buffers, figures out which components to display and
---returns their rendered version.
---@param visible_buffers  Buffer[]
---@param fill_hl string
---@return string
local render = function(visible_buffers, fill_hl)
  local cx = prepare(visible_buffers)
  local rendered = components.render(cx.sidebar_left) .. "%#" .. fill_hl .. "#"
  if config.tabs and config.tabs.placement == "left" then
    rendered = rendered .. components.render(cx.tabs) .. "%#" .. fill_hl .. "#"
  end
  rendered = "%#"
    .. fill_hl
    .. "#"
    .. rendered
    .. components.render(cx.buffers)
    .. "%#"
    .. fill_hl
    .. "#"
    .. string.rep(" ", cx.gap)
    .. components.render(cx.rhs)
  if config.tabs and config.tabs.placement == "right" then
    rendered = rendered .. "%#" .. fill_hl .. "#" .. components.render(cx.tabs)
  end
  rendered = rendered .. components.render(cx.sidebar_right)
  return rendered
end

return {
  by_decreasing_priority = by_decreasing_priority,
  by_increasing_index = by_increasing_index,
  prepare = prepare,
  render = render,
}
