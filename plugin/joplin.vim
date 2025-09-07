" joplin.nvim - Neovim plugin for Joplin integration
" Prevent duplicate loading
if exists('g:loaded_joplin') || v:version < 800
  finish
endif
let g:loaded_joplin = 1

" Define basic commands
command! JoplinPing lua require('joplin').ping()
command! JoplinTest lua require('joplin').test_connection()
command! JoplinFolders lua require('joplin').list_folders()
command! JoplinNotes lua require('joplin').list_notes()

" Set filetype for Joplin notes
augroup joplin_nvim
  autocmd!
  autocmd BufRead,BufNewFile *.joplin.md setfiletype markdown
  autocmd BufRead,BufNewFile joplin://* setfiletype markdown
augroup END