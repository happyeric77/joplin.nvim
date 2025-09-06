local M = {}

local function getenv_or_default(var, default)
	local v = os.getenv(var)
	if v == nil or v == "" then
		return default
	end
	return v
end

M.options = {
	token_env = "JOPLIN_TOKEN",
	token = nil, -- 若直接指定 token
	port = 41184,
	host = "localhost",
	tree = {
		height = 12, -- 樹狀檢視高度
		position = "botright", -- 位置：botright, topleft, etc
		focus_after_open = false, -- 開啟筆記後是否保持焦點在樹狀檢視
		auto_sync = true, -- 自動同步：當切換到 Joplin buffer 時自動同步樹狀視窗
	},
	keymaps = {
		enter = "replace", -- Enter 行為：replace/vsplit
		o = "vsplit", -- o 行為：vsplit/replace
		search = "<leader>js", -- 搜尋快捷鍵
		search_notebook = "<leader>jsnb", -- notebook 搜尋快捷鍵
		toggle_tree = "<leader>jt", -- 切換樹狀檢視快捷鍵
	},
}

function M.setup(opts)
	opts = opts or {}

	-- 深度合併配置
	local function deep_merge(target, source)
		for k, v in pairs(source) do
			if type(v) == "table" and type(target[k]) == "table" then
				deep_merge(target[k], v)
			else
				target[k] = v
			end
		end
	end

	deep_merge(M.options, opts)

	-- 若未直接指定 token，則從環境變數讀取
	if not M.options.token then
		M.options.token = getenv_or_default(M.options.token_env, nil)
	end
end

function M.get_token()
	-- 如果 token 為 nil，嘗試從環境變數讀取
	if not M.options.token then
		M.options.token = getenv_or_default(M.options.token_env, nil)
	end
	return M.options.token
end

function M.get_base_url()
	return string.format("http://%s:%d", M.options.host, M.options.port)
end

return M
