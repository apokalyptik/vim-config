" Run in a real terminal, not -es; records local rendering/edit dispatch only.
set nomore
set lines=40 columns=120
let s:root = g:vimconfig_root
let s:project = s:root . '/.state/benchmark-project'
call mkdir(s:project, 'p')
call writefile(['{"autoload":{"classmap":["./"]}}'], s:project . '/composer.json')
let s:lines = ['<?php']
for s:number in range(0, 499)
  call add(s:lines, printf('function worker_%04d(string $input): string {', s:number))
  for s:step in range(0, 26)
    call add(s:lines, printf("    $value_%02d = $input . '-operation-%02d';", s:step, s:step))
  endfor
  call extend(s:lines, ['    return $value_26;', '}'])
endfor
call writefile(s:lines, s:project . '/large.php')
let s:open_start = reltime()
execute 'edit ' . fnameescape(s:project . '/large.php')
redraw!
let s:open_ms = reltimefloat(reltime(s:open_start)) * 1000
call g:LspEnable()
let s:wait = reltime()
while !g:LspServerReady() && reltimefloat(reltime(s:wait)) < 20
  sleep 20m
endwhile
call assert_true(g:LspServerReady(), 'Benchmark server did not initialize')
call assert_equal('php', &syntax)
call assert_equal(0, get(b:, 'vimconfig_fast', 0), 'Target-sized file entered fast mode')
let s:redraw_start = reltime()
for s:index in range(1, 60)
  call cursor(s:index * 230, 1)
  redraw!
endfor
let s:redraw_ms = reltimefloat(reltime(s:redraw_start)) * 1000 / 60
let s:editing = []
for s:index in range(1, 60)
  call cursor(s:index * 230, 1)
  let s:start = reltime()
  call feedkeys("a \<Esc>", 'xt')
  redraw!
  call add(s:editing, reltimefloat(reltime(s:start)) * 1000)
  " Let asynchronous server work progress between actual edits.
  sleep 20m
endfor
call sort(s:editing, 'f')
let s:report = {'vim': v:version, 'bytes': getfsize(s:project . '/large.php'),
      \ 'lines': line('$'), 'syntax': &syntax, 'fast': get(b:, 'vimconfig_fast', 0),
      \ 'server_ready': g:LspServerReady(), 'open_and_first_redraw_ms': s:open_ms,
      \ 'mean_cursor_and_redraw_ms': s:redraw_ms,
      \ 'median_insert_dispatch_redraw_ms': s:editing[29],
      \ 'p95_insert_dispatch_redraw_ms': s:editing[56],
      \ 'limitations': 'Local PTY and synthetic PHP; excludes SSH latency, physical key input and waiting for server responses.'}
call writefile([json_encode(s:report)], s:root . '/.state/vim-benchmark.json')
call g:LspDisable()
if !empty(v:errors)
  call writefile(v:errors, s:root . '/.state/vim-benchmark-errors')
  cquit
endif
qa!
