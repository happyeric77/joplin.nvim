# joplin.nvim

A Neovim plugin for seamless integration with [Joplin](https://joplinapp.org/), the open-source note-taking and to-do application. This plugin allows you to manage your Joplin notes and notebooks directly from Neovim, providing a powerful and efficient workflow for developers and writers who love both applications.

![joplin.nvim demo](https.user-images.githubusercontent.com/1234567/89012345-abcdef.gif) <!-- Replace with your own demo GIF -->

## Features

- **Interactive Tree Browser**: Browse your Joplin notebooks and notes in a custom tree view.
- **Fuzzy Finding with Telescope**: Quickly search for notes and notebooks using `telescope.nvim`.
- **Full Note Management**: Create, rename, move, and delete notes and notebooks directly from the tree view.
- **Seamless Editing**: Open notes in Neovim buffers and save them back to Joplin automatically.
- **Auto-Sync**: The tree view can automatically sync to the currently opened Joplin note.
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

You can configure `joplin.nvim` by calling the `setup()` function. Here are the default options:

```lua
require("joplin").setup({
  token_env = "JOPLIN_TOKEN", -- Environment variable for Joplin Web Clipper token
  token = nil, -- Directly specify the token here
  port = 41184, -- Joplin Web Clipper port
  host = "localhost", -- Joplin Web Clipper host
  tree = {
    height = 12, -- Tree view height
    position = "botright", -- Tree view position: botright, topleft, etc.
    focus_after_open = false, -- Keep focus on tree view after opening a note
    auto_sync = true, -- Automatically sync tree when switching to a Joplin buffer
  },
  keymaps = {
    enter = "replace", -- Behavior for <CR>: "replace" or "vsplit"
    o = "vsplit", -- Behavior for "o": "vsplit" or "replace"
    search = "<leader>js", -- Keymap for searching notes
    search_notebook = "<leader>jsnb", -- Keymap for searching notebooks
    toggle_tree = "<leader>jt", -- Keymap for toggling the tree view
  },
})
```

**Important**: You need to provide your Joplin Web Clipper authorization token. You can either set the `JOPLIN_TOKEN` environment variable (recommanded) or specify the token directly in the `setup()` function. You can find your token in Joplin's settings under `Web Clipper -> Advanced Options -> Authorization Token`.

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
