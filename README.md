# joplin.nvim

A Neovim plugin for seamless integration with [Joplin](https://joplinapp.org/), the open-source note-taking and to-do application. This plugin allows you to manage your Joplin notes and notebooks directly from Neovim, providing a powerful and efficient workflow for developers and writers who love both applications.

![joplin.nvim demo](https.user-images.githubusercontent.com/1234567/89012345-abcdef.gif) <!-- Replace with your own demo GIF -->

## Features

- **Interactive Tree Browser**: Browse your Joplin notebooks and notes in a custom tree view.
- **Fuzzy Finding with Telescope**: Quickly search for notes and notebooks using `telescope.nvim`.
- **Full Note Management**: Create, rename, move, and delete notes and notebooks directly from the tree view.
- **Seamless Editing**: Open notes in Neovim buffers and save them back to Joplin automatically.
- **Auto-Sync**: The tree view can automatically sync to the currently opened Joplin note.
- **Startup Validation**: Automatically validates Joplin token and Web Clipper availability on plugin load with helpful warning messages.
- **Joplin Connection Test**: A simple command to test the connection to the Joplin Web Clipper service.

## Requirements

- Neovim >= 0.8.0
- [Joplin](https://joplinapp.org/help/install/) installed and running.
- The [Joplin Web Clipper](https://joplinapp.org/clipper/) service must be enabled and running.
- `curl` command-line tool.
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (required for search functionality).
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (dependency for Telescope).
- (Optional) [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons) for icons in the tree view.

## Installation

You can install `joplin.nvim` using your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "happyeric77/joplin.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("joplin").setup({
      -- Your configuration options here
    })
  end,
},
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "happyeric77/joplin.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("joplin").setup({
      -- Your configuration options here
    })
  end,
}
```

## Configuration

```lua
-- Basic setup (using environment variable JOPLIN_TOKEN)
require("joplin").setup()

-- Custom configuration
require("joplin").setup({
  -- API Configuration (flat structure, NOT nested under 'api')
  token_env = "JOPLIN_TOKEN",    -- Environment variable for token
  token = nil,                   -- Or directly specify token (overrides env var)
  port = 41184,
  host = "localhost",
  
  -- Tree view settings
  tree = {
    height = 12,
    position = "botright",
    focus_after_open = false,
    auto_sync = true,
  },
  
  -- Keymap settings
  keymaps = {
    enter = "replace",           -- Enter behavior: replace/vsplit
    o = "vsplit",               -- o behavior: vsplit/replace
    search = "<leader>js",
    search_notebook = "<leader>jsnb",
    toggle_tree = "<leader>jt",
  },
  
  -- Startup validation settings
  startup = {
    validate_on_load = true,     -- Validate requirements on startup
    show_warnings = true,        -- Show warning messages
    async_validation = true,     -- Async validation to avoid blocking
    validation_delay = 100,      -- Delay before validation starts
  },
})
```

**Important Notes:**
- Configuration uses **flat structure** for API settings (not nested under `api`)
- If `token` is specified, it overrides the `token_env` environment variable
- Environment variable `JOPLIN_TOKEN` takes priority unless `token` is explicitly set

**Important**: You need to provide your Joplin Web Clipper authorization token. You can either set the `JOPLIN_TOKEN` environment variable (recommanded) or specify the token directly in the `setup()` function. You can find your token in Joplin's settings under `Web Clipper -> Advanced Options -> Authorization Token`.

## Troubleshooting

### Health Check Diagnostics

The easiest way to diagnose issues is to run the comprehensive health check:

```vim
:checkhealth joplin
```

This will check:
- ✅ System dependencies (curl, network tools)
- ✅ Configuration validation (token, host, port)
- ✅ Joplin connection tests (TCP, Web Clipper, API)
- ✅ Optional dependencies (telescope.nvim)

The health check provides detailed error messages and step-by-step fix instructions for any issues found.

### Quick Connection Test

For a quick connection test, you can use:

```vim
:JoplinPing
```

### Startup Validation

`joplin.nvim` automatically validates your setup when the plugin loads. If you see warnings, here's how to fix them:

#### ⚠️ "Joplin Token Missing" Warning

This means the plugin can't find your Joplin API token. To fix this:

1. **Set environment variable** (recommended):
   ```bash
   export JOPLIN_TOKEN="your_token_here"
   ```

2. **Or configure directly in setup**:
   ```lua
   require("joplin").setup({
     token = "your_token_here"
   })
   ```

3. **Find your token**:
   - Open Joplin Desktop
   - Go to `Tools > Options > Web Clipper`
   - Enable "Enable Web Clipper Service" 
   - Copy the "Authorization token"

#### ⚠️ "Joplin Web Clipper Unavailable" Warning

This means the plugin can't connect to Joplin's Web Clipper service. To fix this:

1. **Ensure Joplin is running**:
   - Start Joplin Desktop application
   - Don't just close it to the system tray

2. **Enable Web Clipper service**:
   - In Joplin, go to `Tools > Options > Web Clipper`
   - Check "Enable Web Clipper Service"
   - Note the port (default: 41184)

3. **Check port availability**:
   ```bash
   curl http://localhost:41184/ping
   # Should return: JoplinClipperServer
   ```

4. **If using non-default port**:
   ```lua
   require("joplin").setup({
     port = 41185, -- Your custom port
   })
   ```

### Disable Validation

If you want to disable startup validation:

```lua
require("joplin").setup({
  startup = {
    validate_on_load = false, -- Disable validation
    show_warnings = false,    -- Disable warning messages
  }
})
```

For more detailed help, run `:JoplinHelp` in Neovim.

## Usage

### Commands

`joplin.nvim` provides the following commands:

- `:JoplinTree`: Open the interactive tree browser.
- `:JoplinFind`: Search for notes using Telescope.
- `:JoplinSearch`: Same as `:JoplinFind`.
- `:JoplinFindNotebook`: Search for notebooks using Telescope.
- `:JoplinBrowse`: Open a simple text-based list browser.
- `:JoplinPing`: Test the connection to the Joplin Web Clipper service.
- `:JoplinHelp`: Show the help message with all commands and keymaps.

### Tree Browser Keymaps

The following keymaps are available in the tree browser:

| Key    | Action                                                                           |
| ------ | -------------------------------------------------------------------------------- |
| `<CR>` | Open a note (behavior defined by `keymaps.enter`) or expand/collapse a notebook. |
| `o`    | Open a note (behavior defined by `keymaps.o`).                                   |
| `a`    | Create a new item (ending with `/` creates a folder, otherwise a note).          |
| `A`    | Create a new folder (shortcut).                                                  |
| `d`    | Delete a note or folder (with confirmation).                                     |
| `r`    | Rename a note or folder.                                                         |
| `m`    | Move a note or folder (uses Telescope to select the destination).                |
| `R`    | Refresh the tree structure.                                                      |
| `q`    | Close the tree browser.                                                          |

### Telescope Search

When searching with `:JoplinFind` or `:JoplinFindNotebook`, you can use the following keymaps in the Telescope window:

| Key     | Action                                      |
| ------- | ------------------------------------------- |
| `<CR>`  | Open the selected note.                     |
| `<C-v>` | Open the selected note in a vertical split. |

## Development

To run the tests for `joplin.nvim`, you can use the following command:

```bash
nvim --headless -c "PlenaryBustedDirectory tests/" -c "qa"
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
