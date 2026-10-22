" Headless: VIM_CONFIG_PROFILE=misc vim -Nu vimrc -i NONE -n -es -S tests/test-ui.vim
" Full completion popups (PTY): TERM=xterm-256color VIM_CONFIG_TEST_POPUPS=1
"   VIM_CONFIG_PROFILE=misc vim -Nu vimrc -i NONE -n -S tests/test-ui.vim
set nomore
set viminfo=
set lines=40 columns=120
call delete('/tmp/vim-config-ui-test-errors')
let s:temp = tempname()
call mkdir(s:temp, 'p')
let g:vimconfig_test_choices = []
function! s:chosen(value) abort
  call add(g:vimconfig_test_choices, a:value)
endfunction
function! VimConfigTestComplete(findstart, base) abort
  return a:findstart ? 0 : ['alpha', 'bravo']
endfunction
let s:items = [
      \ {'label': 'Alpha action', 'action': function('s:chosen', ['alpha'])},
      \ {'label': 'Beta action', 'action': function('s:chosen', ['beta'])},
      \ {'label': 'Gamma action', 'action': function('s:chosen', ['gamma'])}]

try
  call assert_equal('misc', vimconfig#profile())
  call assert_equal(0, &modeline)
  call assert_equal(0, &exrc)
  let s:denies = copy(g:vimconfig_denied_paths)
  let g:vimconfig_denied_paths = ['/nfs']
  call assert_equal(0, g:VimConfigLspPathAllow('/nfs/secret.php'))
  call assert_equal(1, g:VimConfigLspPathAllow('/home/example/allowed.php'))
  let g:vimconfig_denied_paths = s:denies
  call assert_equal('menuone,noinsert,noselect', &completeopt)
  call assert_equal(1, get(g:, 'disable_rainbow_csv_autodetect', 0))
  call assert_equal(0, exists('#RainbowInitAuGrp#BufEnter'))

  call vimconfig#ui#choose('Test actions', s:items)
  call feedkeys("gax\<BS>\<CR>", 'xt')
  call assert_equal(['gamma'], g:vimconfig_test_choices)
  call assert_equal([], popup_list())
  call vimconfig#ui#choose('Test actions', s:items)
  call feedkeys("\<Down>\<CR>", 'xt')
  call assert_equal(['gamma', 'beta'], g:vimconfig_test_choices)
  call vimconfig#ui#choose('Test actions', s:items)
  call feedkeys("no such item\<CR>", 'xt')
  call assert_equal(['gamma', 'beta'], g:vimconfig_test_choices)
  call vimconfig#ui#choose('Test actions', s:items)
  call feedkeys("\<Esc>", 'xt')
  call assert_equal([], popup_list())

  " Without a completion popup, editing keys retain their normal meanings.
  enew
  call assert_equal("\<Up>", vimconfig#ui#edit_key('Up'))
  call assert_equal("\<Down>", vimconfig#ui#edit_key('Down'))
  call assert_equal("\<Left>", vimconfig#ui#edit_key('Left'))
  call assert_equal("\<Right>", vimconfig#ui#edit_key('Right'))
  call assert_equal("\<CR>", vimconfig#ui#enter())
  call assert_equal("\<Tab>", vimconfig#ui#tab())
  call assert_equal("\<Esc>", vimconfig#ui#escape())

  call assert_equal('', &omnifunc)
  call assert_equal('', vimconfig#ui#completion_focus())
  call assert_equal(0, get(b:, 'vimconfig_completion_focus', 0))
  if $VIM_CONFIG_TEST_POPUPS ==# '1'
    " Insert completion popups require an actual terminal display; -es skips
    " rendering and pumvisible() stays false, so run these through a PTY.
    setlocal completefunc=VimConfigTestComplete omnifunc=VimConfigTestComplete
    inoremap <silent> <F10> <C-X><C-U>
    call setline(1, '')
    call feedkeys("i\<F10>\<CR>x\<Esc>", 'xt')
    call assert_equal(['', 'x'], getline(1, '$'))
    %delete _
    call setline(1, ['', ''])
    call cursor(1, 1)
    call feedkeys("i\<F10>\<Down>x\<Esc>", 'xt')
    call assert_equal(['', 'x'], getline(1, '$'))
    %delete _
    call feedkeys("i\<F10>\<F2>\<Down>\<CR>\<Esc>", 'xt')
    call assert_equal('bravo', getline(1))
    %delete _
    " Ordinary typing ends explicit focus. A later automatic popup must
    " leave Enter as a newline instead of accepting its first candidate.
    call feedkeys("i\<F2>x\<F10>\<CR>z\<Esc>", 'xt')
    call assert_equal(['x', 'z'], getline(1, '$'))
    iunmap <F10>
    setlocal completefunc= omnifunc=
    %delete _
  endif

  " F1 opened from insert mode must return to editing after cancellation.
  call feedkeys("iabc\<F1>\<Esc>def\<Esc>", 'xt')
  call assert_equal('abcdef', getline(1))
  call assert_equal([], popup_list())

  " Choosing Save through the same menu preserves insert editing position.
  call writefile([''], s:temp . '/save.txt')
  execute 'edit ' . fnameescape(s:temp . '/save.txt')
  call feedkeys("iabc\<F1>save file\<CR>def\<Esc>", 'xt')
  call assert_equal('abcdef', getline(1))
  call assert_equal(['abc'], readfile(s:temp . '/save.txt'))

  " The menu's Go back action must execute a real Ctrl-O jump.
  call writefile(['one'], s:temp . '/first.txt')
  call writefile(['two'], s:temp . '/second.txt')
  execute 'edit ' . fnameescape(s:temp . '/first.txt')
  execute 'edit ' . fnameescape(s:temp . '/second.txt')
  call vimconfig#ui#menu()
  call feedkeys("go back\<CR>", 'xt')
  call assert_equal(s:temp . '/first.txt', expand('%:p'))

  " Exercise the Bash finder through the real async launcher and popup.
  call mkdir(s:temp . '/.git')
  call writefile(['picked'], s:temp . '/finder selection.txt')
  call vimconfig#ui#files()
  let s:find_start = reltime()
  while empty(popup_list()) && reltimefloat(reltime(s:find_start)) < 5
    sleep 10m
  endwhile
  call assert_false(empty(popup_list()), 'Bash file finder did not open its results')
  if !empty(popup_list())
    call feedkeys("finder selection\<CR>", 'xt')
    call assert_equal(resolve(s:temp . '/finder selection.txt'), resolve(expand('%:p')))
  endif

  " Fast mode is per-buffer and toggling restores the original syntax.
  setlocal filetype=text syntax=text
  let s:first = bufnr('%')
  let s:syntax = &l:syntax
  call vimconfig#toggle_fast()
  call assert_equal(1, b:vimconfig_fast)
  call assert_equal('', &l:syntax)
  new
  call assert_equal(0, get(b:, 'vimconfig_fast', 0))
  execute 'buffer ' . s:first
  call assert_equal(1, b:vimconfig_fast)
  call vimconfig#toggle_fast()
  call assert_equal(s:syntax, &l:syntax)

  " LSP admission must see automatic fast mode before BufEnter, since the
  " vendor attaches from FileType/BufReadPost while a file is opening.
  let s:fast_limit = g:vimconfig_fast_lines
  let g:vimconfig_fast_lines = 2
  let g:vimconfig_test_allow_during_ft = -1
  augroup VimConfigUiTest
    autocmd!
    autocmd FileType php let g:vimconfig_test_allow_during_ft = g:VimConfigLspAllow(bufnr('%'))
  augroup END
  call writefile(['<?php', '// Two', '// Three'], s:temp . '/large.php')
  execute 'edit ' . fnameescape(s:temp . '/large.php')
  call assert_false(g:vimconfig_test_allow_during_ft)
  call assert_equal(1, b:vimconfig_fast)
  let g:vimconfig_fast_lines = s:fast_limit
  augroup VimConfigUiTest
    autocmd!
  augroup END

  " CSV and servers.dat retain the shared statusline after their ftplugins.
  call writefile(['a,b', '1,2'], s:temp . '/data.csv')
  execute 'edit ' . fnameescape(s:temp . '/data.csv')
  call assert_equal('csv', &filetype)
  call assert_equal(g:vimconfig_statusline, &statusline)
  call assert_equal(1, get(b:, 'rbcsv', 0))
  call vimconfig#data#choose_delimiter()
  call feedkeys("tsv\<CR>", 'xt')
  call assert_equal('tsv', &filetype)
  call writefile(['123:dc:1.2.3.4:host.example:10.0.0.1:web:5:extra'], s:temp . '/servers.dat')
  execute 'edit ' . fnameescape(s:temp . '/servers.dat')
  call assert_equal('serversdat', &filetype)
  call assert_equal(g:vimconfig_statusline, &statusline)
  call assert_match('host.example', vimconfig#data#status())
finally
  call delete(s:temp, 'rf')
  call popup_clear()
endtry

if !empty(v:errors)
  call writefile(v:errors, '/tmp/vim-config-ui-test-errors')
  cquit
endif
qa!
