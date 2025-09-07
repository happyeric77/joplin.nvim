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
	startup = {
		validate_on_load = true, -- validate token and web clipper on plugin load
		show_warnings = true, -- show warning messages for missing requirements
		async_validation = true, -- validate web clipper asynchronously to avoid blocking startup
		validation_delay = 100, -- delay in ms before async validation starts
	},
}

function M.setup(opts)
	opts = opts or {}

	-- Support both flat and nested configuration formats for backward compatibility
	-- If user provided nested 'api' configuration, flatten it
	if opts.api then
		-- Move api.* properties to top level
		if opts.api.token_env then opts.token_env = opts.api.token_env end
		if opts.api.token then opts.token = opts.api.token end
		if opts.api.port then opts.port = opts.api.port end
		if opts.api.host then opts.host = opts.api.host end
		-- Remove the nested api object after flattening
		opts.api = nil
	end

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

	-- If token is directly specified, use it (overrides env var)
	-- Otherwise, try to read from the configured environment variable
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
