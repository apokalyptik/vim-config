let s:menus = {}
let s:scan = {}

function! s:filter(id, key) abort
  let l:state = s:menus[a:id]
  if a:key ==# "\<Esc>" || a:key ==# "\<C-C>"
    call popup_close(a:id, -1)
    return 1
  elseif index(["\<Up>", "\<Down>", "\<PageUp>", "\<PageDown>", "\<CR>"], a:key) >= 0
    return popup_filter_menu(a:id, a:key)
  elseif a:key ==# "\<BS>" || a:key ==# "\<Del>" || a:key ==# "\<C-H>"
    let l:state.query = strcharpart(l:state.query, 0, max([0, strchars(l:state.query) - 1]))
  elseif strchars(a:key) == 1 && char2nr(a:key) >= 32
    let l:state.query .= a:key
  else
    return 1
  endif
  let l:state.shown = filter(copy(l:state.items), 's:matches(v:val.label, l:state.query)')
  call popup_settext(a:id, empty(l:state.shown) ? ['(no matches)'] : map(copy(l:state.shown), 'v:val.label'))
  call popup_setoptions(a:id, {'title': ' ' . l:state.title . (empty(l:state.query) ? '' : ': ' . l:state.query) . ' '})
  call win_execute(a:id, 'call cursor(1, 1)')
  return 1
endfunction

function! s:matches(label, query) abort
  for l:word in split(tolower(a:query))
    if stridx(tolower(a:label), l:word) < 0 | return 0 | endif
  endfor
  return 1
endfunction

function! s:chosen(id, result) abort
  let l:state = remove(s:menus, a:id)
  if a:result > 0 && a:result <= len(l:state.shown)
    try
      call call(l:state.shown[a:result - 1].action, [])
    catch
      echohl ErrorMsg | echom 'vim-config: ' . v:exception | echohl None
    endtry
  endif
endfunction

function! vimconfig#ui#choose(title, items) abort
  if empty(a:items) | echo 'No matching items.' | return | endif
  let l:id = popup_menu(map(copy(a:items), 'v:val.label'), {
        \ 'title': ' ' . a:title . ' — type to filter ',
        \ 'filter': function('s:filter'), 'callback': function('s:chosen'),
        \ 'mapping': 0, 'minwidth': min([64, &columns - 6]),
        \ 'maxwidth': max([20, &columns - 6]), 'maxheight': min([18, &lines - 6]),
        \ 'wrap': 0, 'scrollbar': 1, 'padding': [0, 1, 0, 1]})
  let s:menus[l:id] = {'title': a:title, 'query': '', 'items': a:items, 'shown': copy(a:items)}
endfunction

function! s:command(cmd) abort
  if a:cmd ==# 'go-back'
    execute "normal! \<C-O>"
  else
    execute a:cmd
  endif
endfunction

function! s:item(label, cmd) abort
  return {'label': a:label, 'action': function('s:command', [a:cmd])}
endfunction

function! vimconfig#ui#menu() abort
  let l:items = [
        \ s:item('Save file', 'write'),
        \ s:item('Close current panel/window', 'close'),
        \ s:item('Find file in project…', 'call vimconfig#ui#files()'),
        \ s:item('Open file by path…', 'call vimconfig#ui#open_path()'),
        \ s:item('Go to definition', 'LspGotoDefinition'),
        \ s:item('Go back', 'go-back'),
        \ s:item('Find references', 'LspShowReferences'),
        \ s:item('Find callers / incoming calls', 'LspIncomingCalls'),
        \ s:item('Find outgoing calls', 'LspOutgoingCalls'),
        \ s:item('Documentation for symbol', 'LspHover'),
        \ s:item('Symbols in this file', 'LspDocumentSymbol'),
        \ s:item('Search project symbols', 'LspSymbolSearch'),
        \ s:item('Problems in this file', 'LspDiag show'),
        \ s:item('Next problem', 'LspDiag nextWrap'),
        \ s:item('Format file (explicit)', 'LspFormat'),
        \ s:item('Rename symbol…', 'LspRename'),
        \ s:item('Code actions', 'LspCodeAction'),
        \ s:item('Toggle fast mode for this file', 'VimFastMode'),
        \ s:item('Language server status', 'LspShowAllServers'),
        \ s:item('Health and environment', 'VimHealth'),
        \ s:item('Help / keys / setup', 'VimHelp')]
  call extend(l:items, vimconfig#vcs#actions())
  call extend(l:items, vimconfig#data#actions())
  call vimconfig#ui#choose('Actions', l:items)
endfunction

function! vimconfig#ui#completion_focus() abort
  if !pumvisible() && empty(&l:omnifunc)
    let b:vimconfig_completion_focus = 0
    return ''
  endif
  let b:vimconfig_completion_focus = 1
  return pumvisible() ? "\<C-N>" : "\<C-X>\<C-O>"
endfunction

function! vimconfig#ui#edit_key(key) abort
  if pumvisible() && get(b:, 'vimconfig_completion_focus', 0) && index(['Up', 'Down'], a:key) >= 0
    return a:key ==# 'Up' ? "\<C-P>" : "\<C-N>"
  endif
  let b:vimconfig_completion_focus = 0
  let l:motion = {'Up': "\<Up>", 'Down': "\<Down>", 'Left': "\<Left>", 'Right': "\<Right>"}[a:key]
  return (pumvisible() ? "\<C-E>" : '') . l:motion
endfunction

function! vimconfig#ui#enter() abort
  let l:accept = pumvisible() && get(b:, 'vimconfig_completion_focus', 0)
  let b:vimconfig_completion_focus = 0
  return l:accept ? "\<C-Y>" : (pumvisible() ? "\<C-E>" : '') . "\<CR>"
endfunction

function! vimconfig#ui#tab() abort
  let b:vimconfig_completion_focus = 0
  return (pumvisible() ? "\<C-E>" : '') . "\<Tab>"
endfunction

function! vimconfig#ui#escape() abort
  let b:vimconfig_completion_focus = 0
  return pumvisible() ? "\<C-E>" : "\<Esc>"
endfunction

function! vimconfig#ui#open_path() abort
  let l:path = input('Open file: ', '', 'file')
  if !empty(l:path) | execute 'edit ' . fnameescape(l:path) | endif
endfunction

function! s:open_file(path) abort
  if !vimconfig#path_allowed(a:path) | throw 'Path is excluded from project helpers' | endif
  execute 'edit ' . fnameescape(a:path)
endfunction

function! s:scan_line(channel, line) abort
  if stridx(a:line, "ROOT\t") == 0
    let s:scan.root = strpart(a:line, 5)
    return
  endif
  if !empty(a:line) && len(s:scan.paths) < 20000
    call add(s:scan.paths, a:line)
  endif
endfunction

function! s:scan_error(channel, line) abort
  if !empty(a:line) | call add(s:scan.errors, a:line) | endif
endfunction

function! s:scan_closed(channel) abort
  if !empty(s:scan.errors)
    echohl WarningMsg | echom join(s:scan.errors, ' ') | echohl None
  endif
  let l:items = []
  for l:path in sort(s:scan.paths)
    call add(l:items, {'label': l:path, 'action': function('s:open_file', [s:scan.root . '/' . l:path])})
  endfor
  call vimconfig#ui#choose('Files (up to 20,000)', l:items)
  let s:scan = {}
endfunction

function! vimconfig#ui#files() abort
  if !empty(s:scan) | echo 'File search is already running.' | return | endif
  " Root-marker probing happens inside the same isolation as file discovery.
  let l:root = empty(expand('%:p')) ? getcwd() : expand('%:p:h')
  if !vimconfig#path_allowed(l:root) | throw 'Project root is excluded' | endif
  let s:scan = {'root': l:root, 'paths': [], 'errors': []}
  let l:job = vimconfig#job(['perl', vimconfig#root() . '/libexec/find-files.pl', l:root] + g:vimconfig_exclude_names,
        \ {'out_cb': function('s:scan_line'), 'err_cb': function('s:scan_error'), 'close_cb': function('s:scan_closed'), 'out_mode': 'nl', 'err_mode': 'nl'})
  echo 'Finding project files…'
endfunction
