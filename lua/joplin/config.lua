local M = {}

local function getenv_or_default(var, default)
  local v = os.getenv(var)
  if v == nil or v == '' then
    return default
  end
  return v
end

M.options = {
  token_env = 'JOPLIN_TOKEN',
  token = nil, -- 若直接指定 token
  port = 41184,
  host = 'localhost',
}

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.options[k] = v
  end
  -- 若未直接指定 token，則從環境變數讀取
  if not M.options.token then
    M.options.token = getenv_or_default(M.options.token_env, nil)
  end
end

function M.get_token()
  return M.options.token
end

function M.get_base_url()
  return string.format('http://%s:%d', M.options.host, M.options.port)
end

return M
