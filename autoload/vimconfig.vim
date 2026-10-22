let s:profiles = ['container', 'sandbox', 'misc', 'laptop', 'wsl']

function! vimconfig#root() abort
  return g:vimconfig_root
endfunction

function! vimconfig#platform() abort
  if has('mac') && (has('macunix'))
    return 'darwin-arm64'
  endif
  return 'linux-x86_64'
endfunction

function! vimconfig#profile() abort
  return g:vimconfig_profile
endfunction

function! vimconfig#init() abort
  let l:profile = $VIM_CONFIG_PROFILE
  if empty(l:profile) && filereadable(vimconfig#root() . '/.state/profile')
    let l:profile = get(readfile(vimconfig#root() . '/.state/profile', '', 1), 0, '')
  endif
  if empty(l:profile)
    let l:profile = has('macunix') ? 'laptop' : 'container'
  endif
  if index(s:profiles, l:profile) < 0
    throw 'vim-config: unknown profile ' . l:profile
  endif
  let g:vimconfig_profile = l:profile
  let $VIM_CONFIG_PROFILE = l:profile
  let $VIM_CONFIG_ROOT = vimconfig#root()
  let g:vimconfig_denied_paths = get(g:, 'vimconfig_denied_paths', [])
  if l:profile ==# 'sandbox' && index(g:vimconfig_denied_paths, '/nfs') < 0
    call add(g:vimconfig_denied_paths, '/nfs')
  endif
  let $VIM_CONFIG_DENY_PATHS = join(g:vimconfig_denied_paths, "\n")
  let g:vimconfig_exclude_names = get(g:, 'vimconfig_exclude_names', ['.git', '.svn', 'node_modules', '.state'])
  let g:vimconfig_fast_bytes = get(g:, 'vimconfig_fast_bytes', 8 * 1024 * 1024)
  let g:vimconfig_fast_lines = get(g:, 'vimconfig_fast_lines', 100000)
  let g:vimconfig_boot_errors = []
  let g:lsp_options = {
        \ 'autoComplete': v:true, 'autoHighlight': v:false,
        \ 'autoHighlightDiags': v:true, 'autoPopulateDiags': v:false,
        \ 'highlightDiagInline': v:false, 'showDiagWithVirtualText': v:false,
        \ 'showDiagOnStatusLine': v:false, 'showSignature': v:false,
        \ 'hoverOnCursorHold': v:false, 'showInlayHints': v:false,
        \ 'semanticHighlight': v:false, 'useQuickfixForLocations': v:true,
        \ 'keepFocusInReferences': v:true, 'maxDiagnostics': 100,
        \ 'onTypeFormatting': v:false, 'noNewlineInCompletion': v:false}
  " No discovery, shell execution, or download is performed on startup.
  let g:lsp_servers = vimconfig#lsp#servers()
endfunction

function! vimconfig#tool(name) abort
  let l:base = vimconfig#root() . '/.state/tools/' . vimconfig#platform()
  return a:name ==# 'go' ? l:base . '/go/bin/go' : l:base . '/bin/' . a:name
endfunction

function! vimconfig#path_allowed(path) abort
  if empty(a:path)
    return 1
  endif
  let l:path = simplify(fnamemodify(a:path, ':p'))
  for l:denied in g:vimconfig_denied_paths
    let l:deny = substitute(simplify(fnamemodify(l:denied, ':p')), '/\+$', '', '')
    if l:path ==# l:deny || stridx(l:path, l:deny . '/') == 0
      return 0
    endif
  endfor
  " Reject this known symlink lexically, before even inspecting its target.
  if vimconfig#profile() ==# 'sandbox' && l:path =~# '/wp-content/blogs\.dir\%(/\|$\)'
    return 0
  endif
  return 1
endfunction

function! vimconfig#argv(argv) abort
  return [vimconfig#root() . '/bin/helper-run', '--profile', vimconfig#profile(), '--'] + a:argv
endfunction

function! vimconfig#job(argv, opts) abort
  let l:opts = copy(a:opts)
  if has_key(l:opts, 'cwd') && !vimconfig#path_allowed(l:opts.cwd)
    throw 'vim-config: helper working directory is excluded'
  endif
  return job_start(vimconfig#argv(a:argv), l:opts)
endfunction

function! vimconfig#buffer_pre() abort
  let b:vimconfig_denied = !vimconfig#path_allowed(expand('<afile>:p'))
endfunction

function! vimconfig#buffer_enter() abort
  if &buftype !=# '' | return | endif
  if !exists('b:vimconfig_fast')
    let b:vimconfig_fast = line('$') > g:vimconfig_fast_lines || line2byte(line('$') + 1) > g:vimconfig_fast_bytes
  endif
  if b:vimconfig_fast && !get(b:, 'vimconfig_fast_applied', 0) | call vimconfig#apply_fast() | endif
  call vimconfig#data#buffer_setup()
endfunction

function! vimconfig#apply_fast() abort
  if get(b:, 'vimconfig_fast', 0)
    if !get(b:, 'vimconfig_fast_applied', 0) | let b:vimconfig_saved_syntax = &l:syntax | endif
    let b:vimconfig_fast_applied = 1
    setlocal syntax= foldmethod=manual
    if exists('*g:VimConfigLspDetach') | call g:VimConfigLspDetach(bufnr()) | endif
  else
    let b:vimconfig_fast_applied = 0
    let &l:syntax = get(b:, 'vimconfig_saved_syntax', &l:filetype)
    if exists('*g:VimConfigLspAttach') | call g:VimConfigLspAttach(bufnr()) | endif
  endif
endfunction

function! g:VimConfigLspAllow(bnr) abort
  if getbufvar(a:bnr, '&buftype') !=# '' || !vimconfig#path_allowed(bufname(a:bnr))
    return v:false
  endif
  if getbufvar(a:bnr, 'vimconfig_fast', 0)
    return v:false
  endif
  if getbufvar(a:bnr, 'vimconfig_fast', -1) == -1
    let l:info = getbufinfo(a:bnr)
    let l:too_many_lines = !empty(l:info) && l:info[0].linecount > g:vimconfig_fast_lines
    " The loaded buffer's byte count avoids probing the source filesystem.
    let l:too_many_bytes = a:bnr == bufnr() && line2byte(line('$') + 1) > g:vimconfig_fast_bytes
    if l:too_many_lines || l:too_many_bytes
      call setbufvar(a:bnr, 'vimconfig_fast', 1)
      return v:false
    endif
  endif
  return v:true
endfunction

function! g:VimConfigLspPathAllow(path) abort
  return vimconfig#path_allowed(a:path)
endfunction

function! vimconfig#toggle_fast() abort
  let b:vimconfig_fast = !get(b:, 'vimconfig_fast', 0)
  call vimconfig#apply_fast()
  echo 'Fast mode ' . (b:vimconfig_fast ? 'on: syntax and this buffer LSP paused' : 'off')
endfunction

function! vimconfig#ready() abort
  call vimconfig#data#setup()
  call vimconfig#buffer_enter()
  if !executable(vimconfig#tool('phpantom_lsp'))
    echom 'vim-config: run bin/setup once to unpack the included tools. F1 opens actions.'
  endif
endfunction

function! vimconfig#statusline() abort
  let l:extra = substitute(vimconfig#data#status(), '%', '%%', 'g')
  return ' %f %m%r  [' . get(g:, 'vimconfig_profile', '?') . (get(b:, 'vimconfig_fast', 0) ? ' / fast' : '') . '] ' . l:extra . '%= %y  %l:%c  %p%% '
endfunction

function! vimconfig#health() abort
  stopinsert
  botright new
  setlocal buftype=nofile bufhidden=wipe noswapfile
  call setline(1, ['Vim configuration', 'Profile: ' . vimconfig#profile(), 'Platform: ' . vimconfig#platform(), 'Excluded helper roots: ' . string(g:vimconfig_denied_paths), '', 'Run bin/vim-config-doctor --lsp for execution tests.', 'Tools:'] + map(['phpantom_lsp', 'node', 'gopls', 'go'], 'v:val . ": " . (executable(vimconfig#tool(v:val)) ? "ready" : "missing; run bin/setup")'))
  setlocal nomodifiable
endfunction

function! vimconfig#help() abort
  execute 'help vim-config'
endfunction
