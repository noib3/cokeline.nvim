local utils = require('cokeline/utils')
local diagnostics = require('cokeline/diagnostics')

local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
if has_devicons then
  devicons.setup({default = true})
end

local reverse = string.reverse
local insert = table.insert

local contains = vim.tbl_contains
local filter = vim.tbl_filter
local map = vim.tbl_map
local fn = vim.fn

local Buffer = {
  number = 0,
  index = 0,
  is_focused = false,
  is_modified = false,
  is_readonly = false,
  type = '',
  path = '',
  filename = '',
  unique_prefix = '',
  devicon = {
    icon = '',
    color = '',
  },
}

local M = {}

local function get_unique_prefix(filename)
  -- Taken from github.com/famiu/feline.nvim

  if fn.has('win32') == 1 then
    filename = filename:gsub('/', '\\')
  end

  local listed_buffers = fn.getbufinfo({buflisted = 1})
  local filenames = map(function(b)
    return (fn.has('win32') == 0) and b.name or b.name:gsub('/', '\\')
  end, listed_buffers)
  local other_filenames = filter(
    function(f) return filename ~= f end,
    filenames
  )

  if #other_filenames == 0 then
    return fn.fnamemodify(filename, ':t')
  end

  filename = reverse(filename)
  other_filenames = map(reverse, other_filenames)

  local index = math.max(unpack(map(
    function(f)
      for i = 1, #f do
        if filename:sub(i, i) ~= f:sub(i, i) then
          return i
        end
      end
      return 1
    end,
    other_filenames
  )))

  local path_separator = (fn.has('win32') == 0) and '/' or '\\'

  while index <= #filename do
    if filename:sub(index, index) == path_separator then
      index = index - 1
      break
    end

    index = index + 1
  end

  local aux = filename:sub(1, index)
  return reverse(aux:sub(#fn.fnamemodify(reverse(filename), ':t') + 1, #aux))
end

function Buffer:new(b, index)
  local buffer = {}
  local empty_devicon = {
    icon = '',
    color = '',
  }
  setmetatable(buffer, self)
  self.__index = self

  buffer.index = index
  buffer.number = b.bufnr
  buffer.type = vim.bo[b.bufnr].buftype
  buffer.is_focused = (b.bufnr == fn.bufnr('%'))
  buffer.is_modified = vim.bo[b.bufnr].modified
  buffer.is_readonly = vim.bo[b.bufnr].readonly

  if b.name then
    buffer.path = b.name
  end

  if buffer.type == 'quickfix' then
    buffer.filename = '[Quickfix List]'
  elseif #buffer.path > 0 then
    buffer.filename = fn.fnamemodify(buffer.path, ':t')
  else
    buffer.filename = '[No Name]'
  end

  buffer.unique_prefix =
    #fn.getbufinfo({buflisted = 1}) ~= 1
    and get_unique_prefix(buffer.path)
     or ''

  if has_devicons then
    local name =
      buffer.type == 'terminal'
      and 'terminal'
       or fn.fnamemodify(buffer.path, ':t')
    local extension = fn.fnamemodify(buffer.path, ':e')
    local devicon, devicon_hlgroup = devicons.get_icon(name, extension)
    if utils.is_string_empty(devicon)
       or utils.is_string_empty(devicon_hlgroup) then
      buffer.devicon = empty_devicon
    else
      buffer.devicon = {
        icon = devicon .. ' ',
        color = utils.get_hex(devicon_hlgroup, 'fg'),
      }
    end
  else
    buffer.devicon = empty_devicon
  end

  if vim.diagnostic or vim.lsp then
    buffer.lsp = diagnostics.get_status(buffer.number)
  else
    buffer.lsp = {
      errors = 0,
      warnings = 0,
      infos = 0,
      hints = 0,
    }
  end

  return buffer
end

function M.get_listed(order)
  local listed_buffers = fn.getbufinfo({buflisted = 1})
  local buffers = {}

  if not next(order) then
    for i, b in ipairs(listed_buffers) do
      insert(buffers, Buffer:new(b, i))
    end
    return buffers
  end

  local buffer_numbers = {}

  -- First add the buffers whose numbers are in the global 'order' table that
  -- are still listed.
  for _, number in ipairs(order) do
    for _, b in pairs(listed_buffers) do
      if b.bufnr == number then
        insert(buffers, Buffer:new(b, #buffers + 1))
        insert(buffer_numbers, number)
        break
      end
    end
  end

  -- Then add all the listed buffers whose numbers are not yet in the global
  -- 'order' table.
  for _, b in pairs(listed_buffers) do
    if not contains(buffer_numbers, b.bufnr) then
      insert(buffers, Buffer:new(b, #buffers + 1))
    end
  end

  return buffers
end

return M
