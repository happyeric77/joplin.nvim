-- Minimal init for testing
vim.cmd [[set runtimepath=$VIMRUNTIME]]
vim.cmd [[runtime! plugin/plenary.vim]]

-- Add current project to runtimepath
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.cmd("set rtp+=" .. project_root)