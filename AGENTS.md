# joplin.nvim Agent Guidelines

## Test Commands
- **Run tests**: `nvim --headless -c "PlenaryBustedDirectory tests/" -c "qa"`
- **Single test**: `nvim --headless -c "PlenaryBustedFile tests/api_spec.lua" -c "qa"`
- **With minimal init**: `nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedFile tests/api_spec.lua" -c "qa"`
- **No formal lint/build** - manual testing with Joplin Web Clipper service required

## Code Style
- **Language**: Lua (Neovim plugin)
- **Indentation**: 2 spaces, no tabs
- **Imports**: Use `require('module.path')` at file top, assign to `local M = {}`
- **Functions**: Define with `function M.method_name()` for public, `local function` for private
- **Comments**: Chinese comments allowed, use `--` for line comments
- **Error handling**: Use `pcall()` for unsafe operations, `error()` for critical failures

## Naming Conventions
- **Files**: snake_case (e.g., `api_client.lua`)
- **Functions**: snake_case (e.g., `get_base_url()`)
- **Variables**: snake_case, descriptive names
- **Constants**: ALL_CAPS with underscores

## Architecture
- **Entry point**: `lua/joplin/init.lua` with `setup()` function
- **Config**: Centralized in `lua/joplin/config.lua` with environment variable support
- **API**: HTTP client in `lua/joplin/api/client.lua` using `vim.fn.system()` with curl
- **Dependencies**: Requires plenary.nvim for testing, Neo-tree and Telescope for UI integration
- **Token**: Load from `JOPLIN_TOKEN` environment variable or direct config