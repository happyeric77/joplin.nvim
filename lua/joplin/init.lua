local config = require('joplin.config')
local api = require('joplin.api.client')
local endpoints = require('joplin.api.endpoints')

local M = {}

function M.setup(opts)
  config.setup(opts)
end

-- 簡單測試 API 是否可用
function M.ping()
  return api.ping()
end

return M
