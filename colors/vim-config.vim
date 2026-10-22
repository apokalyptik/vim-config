" Quiet terminal colours; keep the user's terminal background.
set background=dark
highlight clear
if exists('syntax_on') | syntax reset | endif
let g:colors_name = 'vim-config'
highlight Normal guifg=#d6d9df guibg=NONE ctermfg=252 ctermbg=NONE
highlight Comment guifg=#89939e ctermfg=245
highlight Constant guifg=#b4c99b ctermfg=150
highlight String guifg=#b4c99b ctermfg=150
highlight Identifier guifg=#d6d9df ctermfg=252 gui=NONE cterm=NONE
highlight Statement guifg=#b8a5d1 ctermfg=146 gui=NONE cterm=NONE
highlight PreProc guifg=#cdb58c ctermfg=180
highlight Type guifg=#91b9cb ctermfg=110 gui=NONE cterm=NONE
highlight Special guifg=#c9b99b ctermfg=180
highlight LineNr guifg=#65717e guibg=NONE ctermfg=242 ctermbg=NONE
highlight SignColumn guifg=#89939e guibg=NONE ctermfg=245 ctermbg=NONE
highlight EndOfBuffer guifg=#49515b ctermfg=239
highlight StatusLine guifg=#d6d9df guibg=#29313b gui=NONE cterm=NONE ctermfg=252 ctermbg=236
highlight StatusLineNC guifg=#89939e guibg=#20262e gui=NONE cterm=NONE ctermfg=245 ctermbg=235
highlight Pmenu guifg=#d6d9df guibg=#252d37 ctermfg=252 ctermbg=235
highlight PmenuSel guifg=#ffffff guibg=#3c4d60 gui=NONE cterm=NONE ctermfg=15 ctermbg=60
highlight PmenuSbar guibg=#29313b ctermbg=236
highlight PmenuThumb guibg=#65717e ctermbg=242
highlight Visual guibg=#3c4d60 ctermbg=60
highlight Search guifg=#e4d8b2 guibg=#454332 ctermfg=223 ctermbg=238
highlight IncSearch guifg=#171c22 guibg=#d6c797 ctermfg=234 ctermbg=180
highlight ErrorMsg guifg=#e89595 guibg=NONE ctermfg=174 ctermbg=NONE
highlight WarningMsg guifg=#d7be89 ctermfg=180
highlight LspDiagSignErrorText guifg=#e89595 guibg=NONE ctermfg=174 ctermbg=NONE
highlight LspDiagSignWarningText guifg=#d7be89 guibg=NONE ctermfg=180 ctermbg=NONE
