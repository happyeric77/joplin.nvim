" joplin.nvim - Neovim plugin for Joplin integration
" 防止重複載入
if exists('g:loaded_joplin') || v:version < 800
  finish
endif
let g:loaded_joplin = 1

" 定義基本命令
command! JoplinPing lua require('joplin').ping()
command! JoplinTest lua require('joplin').test_connection()
command! JoplinFolders lua require('joplin').list_folders()
command! JoplinNotes lua require('joplin').list_notes()

" 設定 Joplin note 的 filetype
augroup joplin_nvim
  autocmd!
  autocmd BufRead,BufNewFile *.joplin.md setfiletype markdown
  autocmd BufRead,BufNewFile joplin://* setfiletype markdown
augroup END