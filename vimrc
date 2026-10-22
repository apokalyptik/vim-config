" Portable Vim configuration. Start with bin/vim-config or source this file.
set nocompatible
let g:vimconfig_root = fnamemodify(resolve(expand('<sfile>:p')), ':h')
let &runtimepath = escape(g:vimconfig_root, ',') . ',' . escape($VIMRUNTIME, ',') . ',' . escape(g:vimconfig_root . '/after', ',')
let &packpath = escape(g:vimconfig_root . '/vendor', ',')
let g:disable_rainbow_csv_autodetect = 1
let g:disable_rainbow_hover = 1
let g:signify_disable_by_default = 1
let g:netrw_nogx = 1
let g:netrw_liststyle = 0
let g:loaded_netrwPlugin = 1
let g:loaded_matchparen = 1
set nomodeline noexrc
set hidden backspace=indent,eol,start
set number nowrap noshowmode
set mouse=
set ttimeout ttimeoutlen=50 timeoutlen=600
set updatetime=500
set completeopt=menuone,noinsert,noselect
set complete=.
set pumheight=10
set shortmess+=c
set noshowmatch
set foldmethod=manual
set signcolumn=yes
set laststatus=2
set wildmenu wildmode=longest:full,full
set ignorecase smartcase incsearch hlsearch
set splitbelow splitright
set expandtab shiftwidth=4 softtabstop=4 tabstop=4
set autoindent
set synmaxcol=8000
set background=dark
if has('termguicolors')
  set termguicolors
endif
if filereadable(g:vimconfig_root . '/local.vim')
  execute 'source ' . fnameescape(g:vimconfig_root . '/local.vim')
endif
call vimconfig#init()
packloadall
call vimconfig#data#setup()
filetype plugin indent on
syntax enable
execute 'colorscheme ' . get(g:, 'vimconfig_colorscheme', 'vim-config')
let g:vimconfig_statusline = '%!vimconfig#statusline()'
let &statusline = g:vimconfig_statusline

nnoremap <silent> <F1> :call vimconfig#ui#menu()<CR>
inoremap <silent><expr> <F1> (pumvisible() ? "\<C-E>" : '') . "\<C-\>\<C-O>:call vimconfig#ui#menu()\<CR>"
xnoremap <silent> <F1> :<C-U>call vimconfig#ui#menu()<CR>
inoremap <silent><expr> <F2> vimconfig#ui#completion_focus()
inoremap <silent><expr> <Up> vimconfig#ui#edit_key('Up')
inoremap <silent><expr> <Down> vimconfig#ui#edit_key('Down')
inoremap <silent><expr> <Left> vimconfig#ui#edit_key('Left')
inoremap <silent><expr> <Right> vimconfig#ui#edit_key('Right')
inoremap <silent><expr> <CR> vimconfig#ui#enter()
inoremap <silent><expr> <Tab> vimconfig#ui#tab()
inoremap <silent><expr> <Esc> vimconfig#ui#escape()
command! VimMenu call vimconfig#ui#menu()
command! VimHealth call vimconfig#health()
command! VimFastMode call vimconfig#toggle_fast()
command! VimFiles call vimconfig#ui#files()
command! VimHelp call vimconfig#help()
augroup VimConfig
  autocmd!
  autocmd VimEnter * call vimconfig#ready()
  autocmd BufReadPre,BufNewFile * call vimconfig#buffer_pre()
  autocmd BufEnter * call vimconfig#buffer_enter()
  autocmd CompleteDone,InsertLeave * let b:vimconfig_completion_focus = 0
  autocmd InsertCharPre * let b:vimconfig_completion_focus = 0
augroup END
