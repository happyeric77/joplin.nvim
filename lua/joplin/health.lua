local M = {}

local config = require "joplin.config"
local api = require "joplin.api.client"

-- Backward compatibility for health functions
local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error
local info = vim.health.info or vim.health.report_info

-- Helper function to test TCP connectivity
local function test_tcp_connection(host, port, timeout)
  timeout = timeout or 5

  -- Try using netcat first (most reliable)
  local nc_cmd = string.format("timeout %d nc -z %s %d 2>/dev/null", timeout, host, port)
  local nc_result = vim.fn.system(nc_cmd)
  local nc_exit_code = vim.v.shell_error

  if nc_exit_code == 0 then
    return true, "Connection successful"
  end

  -- Fallback to telnet if nc is not available
  local telnet_cmd = string.format("timeout %d bash -c 'echo > /dev/tcp/%s/%d' 2>/dev/null", timeout, host, port)
  local telnet_result = vim.fn.system(telnet_cmd)
  local telnet_exit_code = vim.v.shell_error

  if telnet_exit_code == 0 then
    return true, "Connection successful (via telnet)"
  end

  -- Fallback to curl for HTTP ports
  local curl_cmd = string.format("curl -s --connect-timeout %d http://%s:%d/ 2>/dev/null", timeout, host, port)
  local curl_result = vim.fn.system(curl_cmd)
  local curl_exit_code = vim.v.shell_error

  if curl_exit_code == 0 then
    return true, "Connection successful (via curl)"
  end

  return false, "Connection failed - port may be closed or host unreachable"
end

-- Check system dependencies
function M.check_system_dependencies()
  -- Check curl availability
  if vim.fn.executable "curl" == 1 then
    local curl_version = vim.fn.system("curl --version 2>/dev/null | head -1"):gsub("\n", "")
    ok("`curl` found: " .. curl_version)
  else
    error "`curl` not found in PATH"
    info "curl is required for API communication with Joplin"
    info "Install curl from your system package manager:"
    info "  - macOS: brew install curl"
    info "  - Ubuntu/Debian: sudo apt install curl"
    info "  - CentOS/RHEL: sudo yum install curl"
    return false
  end

  -- Check for network tools (optional but helpful for diagnostics)
  local has_nc = vim.fn.executable "nc" == 1
  local has_telnet = vim.fn.executable "telnet" == 1

  if has_nc or has_telnet then
    local tools = {}
    if has_nc then
      table.insert(tools, "nc")
    end
    if has_telnet then
      table.insert(tools, "telnet")
    end
    info("Network diagnostic tools available: " .. table.concat(tools, ", "))
  else
    warn "No network diagnostic tools found (nc, telnet)"
    info "Installing nc or telnet can help with connection diagnostics"
  end

  return true
end

-- Check configuration
function M.check_configuration()
  local config_ok = true

  -- Check token configuration
  local token = config.get_token()
  local token_env = config.options.token_env or "JOPLIN_TOKEN"

  if token and token ~= "" then
    if config.options.token then
      ok "Token configured directly in setup()"
      info "Using token from setup() configuration"
    else
      ok("Token configured via environment variable: `" .. token_env .. "`")
      info("Token length: " .. string.len(token) .. " characters")
    end
  else
    error "No token configured"
    info "Joplin API token is required for authentication"
    info "Set token using one of these methods:"
    info("  1. Environment variable: export " .. token_env .. "='your_token_here'")
    info "  2. Direct configuration: require('joplin').setup({token = 'your_token_here'})"
    info "  3. Custom env var: require('joplin').setup({token_env = 'CUSTOM_TOKEN_VAR'})"
    info ""
    info "To get your token:"
    info "  1. Open Joplin Desktop"
    info "  2. Go to Tools > Options > Web Clipper"
    info "  3. Enable 'Enable Web Clipper Service'"
    info "  4. Copy the Authorization token"
    config_ok = false
  end

  -- Check host configuration
  local host = config.options.host or "localhost"
  if host and host ~= "" then
    if host == "localhost" or host == "127.0.0.1" then
      ok("Host configured: " .. host .. " (local)")
    else
      info("Host configured: " .. host .. " (remote)")
      warn "Remote Joplin connections may require additional network configuration"
    end
  else
    error "Host not configured"
    config_ok = false
  end

  -- Check port configuration
  local port = config.options.port or 41184
  if port and type(port) == "number" and port > 0 and port <= 65535 then
    ok("Port configured: " .. tostring(port))
    if port ~= 41184 then
      info "Using non-default port (default is 41184)"
    end
  else
    error("Invalid port configuration: " .. tostring(port))
    info "Port must be a number between 1 and 65535"
    config_ok = false
  end

  -- Show current base URL
  if config_ok then
    local base_url = config.get_base_url()
    info("Joplin Web Clipper URL: " .. base_url)
  end

  return config_ok
end

-- Check Joplin connection
function M.check_joplin_connection()
  local host = config.options.host or "localhost"
  local port = config.options.port or 41184
  local base_url = config.get_base_url()

  -- First, test TCP connectivity
  info("Testing TCP connectivity to " .. host .. ":" .. port .. "...")
  local tcp_ok, tcp_msg = test_tcp_connection(host, port, 5)

  if not tcp_ok then
    error("Cannot establish TCP connection to " .. host .. ":" .. port)
    info(tcp_msg)
    info "Troubleshooting steps:"
    info "  1. Ensure Joplin Desktop application is running"
    info "  2. Check if Web Clipper service is enabled:"
    info "     - Go to Tools > Options > Web Clipper"
    info "     - Enable 'Enable Web Clipper Service'"
    info "  3. Verify the port number (default: 41184)"
    info "  4. Check firewall settings if using remote host"
    return false
  else
    ok("TCP connection established: " .. tcp_msg)
  end

  -- Test Web Clipper service ping
  info "Testing Web Clipper service..."
  local ping_ok, ping_result = api.ping()

  if not ping_ok then
    error "Web Clipper service not responding"
    info("Response: " .. tostring(ping_result))
    info "The port is reachable but Web Clipper service is not responding"
    info "Troubleshooting steps:"
    info "  1. Restart Joplin Desktop application"
    info "  2. Re-enable Web Clipper service:"
    info "     - Go to Tools > Options > Web Clipper"
    info "     - Disable and re-enable 'Enable Web Clipper Service'"
    info "  3. Check Joplin logs for errors"
    return false
  else
    ok("Web Clipper service responding: " .. tostring(ping_result))
  end

  -- Test token validity by attempting to fetch folders
  info "Testing API token validity..."
  local folders_ok, folders_result = api.get_folders()

  if not folders_ok then
    error "API token validation failed"
    info("Error: " .. tostring(folders_result))
    info "The Web Clipper service is running but token is invalid"
    info "Troubleshooting steps:"
    info "  1. Verify your token in Joplin:"
    info "     - Go to Tools > Options > Web Clipper"
    info "     - Copy the Authorization token"
    info "  2. Update your token configuration:"
    info "     - Environment: export JOPLIN_TOKEN='correct_token'"
    info "     - Or setup: require('joplin').setup({token = 'correct_token'})"
    info "  3. Restart Neovim after updating the token"
    return false
  else
    ok("API token valid - found " .. #folders_result .. " notebooks")
    if #folders_result > 0 then
      info("Sample notebooks: " .. table.concat(
        vim.tbl_map(function(f)
          return f.title or "Untitled"
        end, vim.list_slice(folders_result, 1, math.min(3, #folders_result))),
        ", "
      ))
    end
  end

  return true
end

-- Check optional dependencies
function M.check_optional_dependencies()
  -- Check telescope.nvim
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    ok "`telescope.nvim` found - search functionality available"
    info "Commands available: :JoplinFind, :JoplinSearch, :JoplinFindNotebook"
  else
    warn "`telescope.nvim` not found - search functionality disabled"
    info "Install telescope.nvim to enable search features:"
    info "  - With lazy.nvim: {'nvim-telescope/telescope.nvim'}"
    info "  - With packer: use 'nvim-telescope/telescope.nvim'"
    info "Search commands will show error message until telescope is installed"
  end

  -- Check plenary.nvim (usually comes with telescope)
  local has_plenary = pcall(require, "plenary")
  if has_plenary then
    ok "`plenary.nvim` found"
  else
    if has_telescope then
      warn "`plenary.nvim` not found but telescope is available"
      info "This might cause issues - plenary is usually bundled with telescope"
    else
      info "`plenary.nvim` not found (expected if telescope is not installed)"
    end
  end

  -- Check if we're in a compatible Neovim version
  local nvim_version = vim.version()
  local version_str = string.format("%d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch)

  if nvim_version.major == 0 and nvim_version.minor >= 8 then
    ok("Neovim version compatible: " .. version_str)
  elseif nvim_version.major > 0 then
    ok("Neovim version compatible: " .. version_str)
  else
    warn("Neovim version may be too old: " .. version_str)
    info "Neovim 0.8+ is recommended for best compatibility"
  end
end

-- Main health check function
function M.check()
  start "joplin.nvim"
  info "Joplin.nvim - Joplin note management plugin for Neovim"
  info "GitHub: https://github.com/andynameistaken/joplin.nvim"

  -- System dependencies
  start "System Dependencies"
  local system_ok = M.check_system_dependencies()

  -- Configuration
  start "Configuration"
  local config_ok = M.check_configuration()

  -- Only test connection if basic requirements are met
  if system_ok and config_ok then
    start "Joplin Connection"
    M.check_joplin_connection()
  else
    start "Joplin Connection"
    error "Skipping connection tests - fix system dependencies and configuration first"
  end

  -- Optional dependencies (always check)
  start "Optional Dependencies"
  M.check_optional_dependencies()

  -- Final summary
  start "Summary"
  if system_ok and config_ok then
    info "Run :JoplinPing to test connection manually"
    info "Run :JoplinHelp for detailed usage instructions"
    info "Run :JoplinTree to open the file browser"
  else
    warn "Fix the errors above before using joplin.nvim"
    info "Run :checkhealth joplin again after making changes"
  end
end

return M
