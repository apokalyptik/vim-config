" User-invoked, asynchronous VCS actions. No recursive background polling.
let s:serial = 0

function! s:warn(message) abort
  echohl WarningMsg
  echomsg 'Vim Config: ' . a:message
  echohl None
endfunction

function! s:context() abort
  if exists('b:vimconfig_vcs_context')
    let context = copy(b:vimconfig_vcs_context)
    return vimconfig#path_allowed(context.root) && vimconfig#path_allowed(context.file) ? context : {}
  endif
  let file = expand('%:p')
  if empty(file) || !vimconfig#path_allowed(file)
    call s:warn('Open a file outside excluded paths first.')
    return {}
  endif
  let dir = fnamemodify(file, ':h')
  " Stop at a bounded ancestor depth, checking the guard before any metadata.
  for depth in range(0, 31)
    if !vimconfig#path_allowed(dir)
      break
    endif
    for [kind, marker] in [['git', '.git'], ['svn', '.svn']]
      let candidate = dir . '/' . marker
      if vimconfig#path_allowed(candidate) && !empty(getftype(candidate))
        let relative = strpart(file, strlen(dir) + (dir ==# '/' ? 0 : 1))
        return {'kind': kind, 'root': dir, 'file': file, 'relative': relative}
      endif
    endfor
    let parent = fnamemodify(dir, ':h')
    if parent ==# dir
      break
    endif
    let dir = parent
  endfor
  call s:warn('No Git or SVN working tree found within 32 parent directories.')
  return {}
endfunction

function! s:git() abort
  let argv = ['git', '--no-pager', '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false']
  if vimconfig#profile() ==# 'container'
    let argv += ['-c', 'index.threads=1', '-c', 'pack.threads=1', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false']
  endif
  return argv
endfunction

function! s:append(buf, text) abort
  if !bufexists(a:buf)
    return
  endif
  " Cap accumulated output: huge histories/diffs must not freeze Vim.
  let line_count = getbufinfo(a:buf)[0].linecount
  if line_count >= 20000
    if !getbufvar(a:buf, 'vimconfig_vcs_truncated', 0)
      call setbufvar(a:buf, '&modifiable', 1)
      call appendbufline(a:buf, '$', '[Output truncated at 20,000 lines.]')
      call setbufvar(a:buf, '&modifiable', 0)
      call setbufvar(a:buf, 'vimconfig_vcs_truncated', 1)
    endif
    return
  endif
  call setbufvar(a:buf, '&modifiable', 1)
  call appendbufline(a:buf, '$', a:text)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

function! s:output(buf, channel, message) abort
  call s:append(a:buf, a:message)
endfunction

function! s:exit(buf, cleanup, job, status) abort
  call setbufvar(a:buf, 'vimconfig_vcs_exit', a:status)
  call setbufvar(a:buf, 'vimconfig_vcs_running', 0)
  if a:status != 0
    call s:append(a:buf, '[Command exited with status ' . a:status . ']')
  endif
  if !empty(a:cleanup)
    call delete(a:cleanup)
  endif
  redrawstatus
endfunction

function! s:run(context, label, argv, filetype, ...) abort
  if !vimconfig#path_allowed(a:context.root) || !vimconfig#path_allowed(a:context.file)
    call s:warn('The working path is excluded.')
    return
  endif
  let cleanup = a:0 ? a:1 : ''
  let s:serial += 1
  botright 12new
  execute 'file ' . fnameescape('[VCS ' . a:label . ' ' . s:serial . ']')
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nowrap
  let b:vimconfig_vcs_context = copy(a:context)
  let b:vimconfig_vcs_running = 1
  let b:vimconfig_vcs_truncated = 0
  let &l:filetype = a:filetype
  call setline(1, a:label . ' — ' . a:context.root)
  setlocal nomodifiable
  stopinsert
  let buf = bufnr('%')
  try
    let job = vimconfig#job(a:argv, {'cwd': a:context.root,
          \ 'out_mode': 'nl', 'err_mode': 'nl',
          \ 'out_cb': function('s:output', [buf]),
          \ 'err_cb': function('s:output', [buf]),
          \ 'exit_cb': function('s:exit', [buf, cleanup])})
    if job_status(job) ==# 'fail'
      throw 'Could not start ' . a:argv[0]
    endif
    let b:vimconfig_vcs_job = job
  catch
    let b:vimconfig_vcs_running = 0
    call s:append(buf, v:exception)
    if !empty(cleanup)
      call delete(cleanup)
    endif
  endtry
endfunction

function! vimconfig#vcs#status() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  let argv = ctx.kind ==# 'git'
        \ ? s:git() + ['--no-optional-locks', 'status', '--short', '--branch', '--untracked-files=normal']
        \ : ['svn', '--non-interactive', 'status', '--ignore-externals', '.']
  call s:run(ctx, toupper(ctx.kind) . ' status', argv, '')
endfunction

function! vimconfig#vcs#diff() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  let argv = ctx.kind ==# 'git'
        \ ? s:git() + ['diff', '--no-ext-diff', '--no-textconv', '--', ctx.relative]
        \ : ['svn', '--non-interactive', 'diff', '--internal-diff', '--', ctx.relative . '@']
  call s:run(ctx, toupper(ctx.kind) . ' file diff (saved content)', argv, 'diff')
endfunction

function! vimconfig#vcs#log() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  let argv = ctx.kind ==# 'git'
        \ ? s:git() + ['log', '-50', '--date=short', '--format=%h %ad %an%n%s%n', '--', ctx.relative]
        \ : ['svn', '--non-interactive', 'log', '--limit', '50', '--', ctx.relative . '@']
  call s:run(ctx, toupper(ctx.kind) . ' file history' . (ctx.kind ==# 'svn' ? ' (network)' : ''), argv, '')
endfunction

function! vimconfig#vcs#blame() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  let argv = ctx.kind ==# 'git'
        \ ? s:git() + ['blame', '--date=short', '--', ctx.relative]
        \ : ['svn', '--non-interactive', 'blame', '--', ctx.relative . '@']
  call s:run(ctx, toupper(ctx.kind) . ' file blame' . (ctx.kind ==# 'svn' ? ' (network)' : ''), argv, '')
endfunction

function! vimconfig#vcs#add() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  if &modified
    call s:warn('Save the file before staging/adding it.')
    return
  endif
  " Exactly the current file: never stage a whole project implicitly.
  let argv = ctx.kind ==# 'git' ? s:git() + ['add', '--', ctx.relative]
        \ : ['svn', '--non-interactive', 'add', '--depth', 'empty', '--', ctx.relative . '@']
  call s:run(ctx, toupper(ctx.kind) . ' stage/add current file', argv, '')
endfunction

function! vimconfig#vcs#commit() abort
  let ctx = s:context()
  if empty(ctx) | return | endif
  let s:serial += 1
  botright 10new
  execute 'file ' . fnameescape('[Commit message ' . s:serial . ']')
  setlocal buftype=nofile bufhidden=hide noswapfile filetype=gitcommit
  let b:vimconfig_vcs_context = ctx
  let b:vimconfig_commit_draft = 1
  let help = ctx.kind ==# 'git' ? '# Commits the staged Git index. Review VCS status first.'
        \ : '# Commits the current SVN file; contacts the repository server.'
  call setline(1, ['', help, '# Type the message above. F1 → Submit commit sends it.',
        \ '# Lines beginning with # are removed. Closing this buffer sends nothing.'])
  call cursor(1, 1)
  startinsert
endfunction

function! vimconfig#vcs#submit_commit() abort
  if !get(b:, 'vimconfig_commit_draft', 0)
    call s:warn('Open a commit message draft first.')
    return
  endif
  if get(b:, 'vimconfig_commit_submitted', 0)
    call s:warn('This draft was already submitted. Review the result before creating another.')
    return
  endif
  let ctx = s:context()
  if empty(ctx) | return | endif
  let message = filter(getline(1, '$'), 'v:val !~# "^#"')
  if empty(substitute(join(message, "\n"), '\s', '', 'g'))
    call s:warn('The commit message is empty.')
    return
  endif
  let message_file = tempname()
  call writefile(message, message_file)
  call setfperm(message_file, 'rw-------')
  let b:vimconfig_commit_submitted = 1
  let argv = ctx.kind ==# 'git' ? s:git() + ['commit', '--file', message_file]
        \ : ['svn', '--non-interactive', 'commit', '--file', message_file, '--', ctx.relative . '@']
  call s:run(ctx, toupper(ctx.kind) . ' commit' . (ctx.kind ==# 'svn' ? ' (network)' : ''), argv, '', message_file)
endfunction

function! vimconfig#vcs#actions() abort
  return [
        \ {'label': 'VCS: Status', 'action': function('vimconfig#vcs#status')},
        \ {'label': 'VCS: Diff current file (saved content)', 'action': function('vimconfig#vcs#diff')},
        \ {'label': 'VCS: File history (SVN uses network)', 'action': function('vimconfig#vcs#log')},
        \ {'label': 'VCS: File blame (SVN uses network)', 'action': function('vimconfig#vcs#blame')},
        \ {'label': 'VCS: Stage/add saved current file', 'action': function('vimconfig#vcs#add')},
        \ {'label': 'VCS: Write commit message', 'action': function('vimconfig#vcs#commit')},
        \ {'label': 'VCS: Submit commit (SVN uses network)', 'action': function('vimconfig#vcs#submit_commit')}]
endfunction
