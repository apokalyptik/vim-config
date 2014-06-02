set nocompatible              " be iMproved, required
filetype off                  " Turn off temporarily for Vundle

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'gmarik/Vundle.vim'				" Vundle, this one should never be removed					github.com/gmarik/Vundle.vim
Plugin 'majutsushi/tagbar'				" Tag bar													github.com/majutsushi/tagbar
Plugin 'Shougo/neocomplete.vim'			" keyword completion										github.com/Shougo/neocomplete.vim
Plugin 'Shougo/neosnippet.vim'			" Snippets support (make things you do a low... faster)		github.com/Shougo/neosnippet.vim
Plugin 'Shougo/neosnippet-snippets'		" Snippets													github.com/Shougo/neosnippet-snippets
Plugin 'Shougo/vimproc.vim'				" Asynchronous execution plugin for Vim						github.com/Shougo/vimproc.vim
Plugin 'scrooloose/nerdtree'			" Directory listing/browsing inside vim						github.com/scrooloose/nerdtree
Plugin 'tpope/vim-fugitive'				" Add some git support										github.com/tpope/vim-fugitive
Plugin 'tpope/vim-git'					" git syntax highlighting, etc								github.com/tpope/vim-git
Plugin 'bling/vim-airline'				" nicer, more informative status lines						github.com/bling/vim-airline
Plugin 'vim-scripts/SQLUtilities'		" SQL tilities												github.com/vim-scripts/SQLUtilities
Plugin 'nvie/vim-togglemouse'			" f12 (fn+ctrl+f12 on osx) to toggle mouse on and off		github.com/nvie/vim-togglemouse
Plugin 'scrooloose/syntastic'			" Syntax checking on the fly                                github.com/scrooloose/syntastic
Plugin 'fatih/vim-go'					" Go language features										github.com/fatih/vim-go
call vundle#end()
filetype plugin indent on " turn back on file type plugins, allow indent config per file type

" Shougo/vimproc.vim
if 0 == glob("~/.vim/bundle/vimproc.vim/autoload/vimproc_*.so")
	call system("cd ~/.vim/bundle/vimproc.vim/ && make")
endif


" nvie/vim-togglemouse notes
	" I have (in iTerm2) alt+middle-mouse mapped to type 'Send Escape Sequence...': ESC+ '[24~'
	" which sends f12 (this doesn't work with shift, option, or plain middle mouse well (we get
	" into mouse mode, but not out of it), alt-middlebutton seems to work fine for both

" scrooloose/syntastic Configuration
	let g:syntastic_aggregate_errors = 1
	let g:syntastic_quiet_messages = { "type": "style" }
	let g:syntastic_always_populate_loc_list = 1
	let g:syntastic_check_on_open = 1
	let g:syntastic_auto_loc_list = 1

" vim-scripts/SQLUtilities Configuration
	vmap <silent>sf        <Plug>SQLU_Formatter<CR>
	nmap <silent>scl       <Plug>SQLU_CreateColumnList<CR>
	nmap <silent>scd       <Plug>SQLU_GetColumnDef<CR>
	nmap <silent>scdt      <Plug>SQLU_GetColumnDataType<CR>
	nmap <silent>scp       <Plug>SQLU_CreateProcedure<CR>

" scrooloose/nerdtree Configuration
	" Ctrl+N to toggle NerdTree
	map <C-n> :NERDTreeToggle<CR>
	" If nerdtree is the only thing left then quit
	autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif

" use Ctrl+T to toggle majutsushi/tagbar
	nmap <C-t> :TagbarToggle<CR>

" Shougo/neosnippet.vim Configuration
	" Plugin key-mappings.
	imap <C-k>     <Plug>(neosnippet_expand_or_jump)
	smap <C-k>     <Plug>(neosnippet_expand_or_jump)
	xmap <C-k>     <Plug>(neosnippet_expand_target)

	" SuperTab like snippets behavior.
	imap <expr><TAB> neosnippet#expandable_or_jumpable() ?
	\ "\<Plug>(neosnippet_expand_or_jump)"
	\: pumvisible() ? "\<C-n>" : "\<TAB>"
	smap <expr><TAB> neosnippet#expandable_or_jumpable() ?
	\ "\<Plug>(neosnippet_expand_or_jump)"
	\: "\<TAB>"

	" For snippet_complete marker.
	if has('conceal')
	  set conceallevel=2 concealcursor=i
	endif

	" Load local snippets
	call system('mkdir -p ~/.vim/snips')
	let g:neosnippet#snippets_directory = "~/.vim/snips"


" Shougo/neocomplete.vim Configuration
	call system('mkdir -p ~/.vim/.cache/neocomplete')
	let g:neocomplete#data_directory='~/.vim/.cache/neocomplete'
	let g:acp_enableAtStartup = 0
	let g:neocomplete#enable_ignore_case = 1
	let g:neocomplete#enable_smart_case = 1
	let g:neocomplete#enable_auto_select = 1
	let g:neocomplete#enable_at_startup = 1
	let g:neocomplete#enable_smart_case = 1
	let g:neocomplete#sources#syntax#min_keyword_length = 3
	let g:neocomplete#lock_buffer_name_pattern = '\*ku\*'
	let g:neocomplete#sources#dictionary#dictionaries = {
		\ 'default' : '',
		\ 'vimshell' : $HOME.'/.vimshell_hist',
		\ 'scheme' : $HOME.'/.gosh_completions'
			\ }
	if !exists('g:neocomplete#keyword_patterns')
		let g:neocomplete#keyword_patterns = {}
	endif
	let g:neocomplete#keyword_patterns['default'] = '\h\w*'

" bling/vim-airline configuration
	let g:airline#extensions#tabline#enabled = 1

" Use persistent undo
if has("persistent_undo")
	call system('mkdir ~/.vim/undodir')
	set undodir=~/.vim/undodir
	set undofile
	set undolevels=1000 " maximum number of changes that can be undone
	set undoreload=10000 " maximum number lines to save for undo on a buffer reload
endif

let html_use_css=1			" generate valid HTML 4.01 markup with CSS1 styling
let use_xhtml=1				" generate XHTML 1.0 instead (XML compliant HTML)
syntax on					" Enable syntax highlighting
set ai						" when in doubt return, in edit mode, indents to the current indentation level
set smartindent				" lines ending in a { indent. lines ending in a } outdent
set backspace=2				" backspace will be able to continue past the current line onto the previous line
set hidden					" allow opening new files/buffers if the current one has unsaved changes
set history=50				" keep 50 lines of command line history
set hlsearch				" highlight all search matches
set ignorecase smartcase	" case-insensitvice search unless upper-case letters
set laststatus=2			" always show a status line
set nolazyredraw			" don't do lazy redrawing
set linebreak				" wrap lines when displaying but don't add them to the file, obviously
set incsearch				" do incremental searching
set modeline				" honor modelines ( http://vim.wikia.com/wiki/Modeline_magic )
set noexpandtab				" insert tabs instead of spaces
set ruler					" show the cursor position all the time
set scrolloff=2				" move the display buffer when you're this close to the end of the "page" "on screen"
set scrolljump=3			" when we do scroll off the edfe jump this many lines
set shiftwidth=4			" Number of spaces to use for each step of (auto)indent
set shortmess=aI			" avoid anoyting hit ENTER stuff at prompt
set showcmd					" display incomplete commands
set showmode				" If in Insert, Replace or Visual mode put a message on the last line.
set showmatch				" Show matching braces and parens
set softtabstop=4			" Number of spaces that a <Tab> counts for while performing editing operations, like inserting a <Tab> or using <BS>
set smartcase				" Override the 'ignorecase' option if the search pattern contains upper case characters.
set tabstop=4				" Number of spaces that a <Tab> in the file counts for.
set wildmenu				" Make use of the "status line" to show possible completions of command line commands, file names, and more.
set wrap linebreak nolist   " soft line wrap
set wildmode=list:longest,full
							" When more than one match, list all matches and complete till longest common string. Complete the next full match
set ttimeoutlen=100 timeoutlen=5000
							" The time in milliseconds that is waited for a key code or mapped key sequence to complete.d
set statusline=%<[%n]\ %F\ %m%r%y%=%-14.(%l,%c%V%)\ %P

""" Color Scheme
colorscheme vividchalk

" change the directory only for the current window to the directory of the opened file
autocmd BufEnter * lcd %:p:h

" Provide easy updating of vim via :call UpdateVimrc()
function! UpdateVimrc()
    call system("wget -O ~/.vimrc 'https://github.com/apokalyptik/vim-config/raw/master/.vimrc'")
    source ~/.vimrc
    silent PluginClean!
    silent PluginInstall!
    q!
    source ~/.vimrc
    silent edit!
endfunction
