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
	token = nil, -- if directly specifying token
	port = 41184,
	host = "localhost",
	tree = {
		height = 12, -- tree view height
		position = "botright", -- position: botright, topleft, etc
		focus_after_open = false, -- keep focus on tree view after opening note
		auto_sync = true, -- auto sync: automatically sync tree window when switching to Joplin buffer
	},
	keymaps = {
		enter = "replace", -- Enter behavior: replace/vsplit
		o = "vsplit", -- o behavior: vsplit/replace
		search = "<leader>js", -- search shortcut key
		search_notebook = "<leader>jsnb", -- notebook search shortcut key
		toggle_tree = "<leader>jt", -- toggle tree view shortcut key
	},
}

function M.setup(opts)
	opts = opts or {}

	-- Deep merge configuration
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

	-- If token is not directly specified, read from environment variable
	if not M.options.token then
		M.options.token = getenv_or_default(M.options.token_env, nil)
	end
end

function M.get_token()
	-- If token is nil, try to read from environment variable
	if not M.options.token then
		M.options.token = getenv_or_default(M.options.token_env, nil)
	end
	return M.options.token
end

function M.get_base_url()
	return string.format("http://%s:%d", M.options.host, M.options.port)
end

return M
