local config = require('joplin.config')
local M = {}

local function build_url(path, params)
  local base = config.get_base_url() .. path
  params = params or {}
  params.token = config.get_token()
  local query = {}
  for k, v in pairs(params) do
    table.insert(query, string.format('%s=%s', k, vim.fn.escape(v, ',')))
  end
  if #query > 0 then
    return base .. '?' .. table.concat(query, '&')
  else
    return base
  end
end

-- 基本 GET 請求
function M.get(path, params)
  local url = build_url(path, params)
  local cmd = string.format('curl -s "%s"', url)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error('Joplin API GET failed: ' .. result)
  end
  return vim.fn.json_decode(result)
end

-- 基本 POST 請求
function M.post(path, data, params)
  local url = build_url(path, params)
  local json_data = vim.fn.json_encode(data or {})
  local cmd = string.format('curl -s -X POST -H "Content-Type: application/json" -d %s "%s"',
    vim.fn.shellescape(json_data), url)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error('Joplin API POST failed: ' .. result)
  end
  return vim.fn.json_decode(result)
end

-- 測試 /ping
function M.ping()
  local url = build_url('/ping')
  local cmd = string.format('curl -s "%s"', url)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false, result
  end
  return result:match('JoplinClipperServer') ~= nil, result
end

return M
