" Real offline PHPantom integration through the configured Vim LSP client.
" Run: VIM_CONFIG_PROFILE=misc vim -Nu vimrc -i NONE -n -es -S tests/test-lsp-client.vim
set nomore
set viminfo=
let s:repo = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:temp = tempname()
let s:report = []
call mkdir(s:temp . '/src', 'p')
let s:temp = resolve(s:temp)
let $XDG_CACHE_HOME = s:temp . '/cache'
let $XDG_CONFIG_HOME = s:temp . '/config'
let $GOTELEMETRY = 'off'
for s:name in ['composer.json', 'app.php', 'src/Greeter.php']
  call writefile(readfile(s:repo . '/tests/fixtures/php-lsp/' . s:name), s:temp . '/' . s:name)
endfor
" Keep real navigation targets while exercising the requested large-file scale.
let s:large = readfile(s:temp . '/app.php')
for s:number in range(500)
  call add(s:large, printf('function vim_config_worker_%04d(string $input): string {', s:number))
  for s:step in range(27)
    call add(s:large, printf("    $value_%02d = $input . '-op-%02d';", s:step, s:step))
  endfor
  call extend(s:large, ['    return $value_26;', '}'])
endfor
call writefile(s:large, s:temp . '/app.php')
function! s:wait_ready(milliseconds) abort
  let l:start = reltime()
  while reltimefloat(reltime(l:start)) * 1000 < a:milliseconds
    if exists('*g:LspServerReady') && g:LspServerReady()
      return 1
    endif
    sleep 20m
  endwhile
  return 0
endfunction
try
  " -S runs before VimEnter; initialize the same client explicitly for tests.
  call g:LspEnable()
  execute 'edit ' . fnameescape(s:temp . '/app.php')
  call assert_equal('php', &filetype)
  call assert_equal(0, get(b:, 'vimconfig_fast', 0), 'representative PHP file entered reduced mode')
  call add(s:report, 'fixture_bytes=' . string(getfsize(s:temp . '/app.php')))
  call add(s:report, 'fixture_lines=' . string(line('$')))
  let s:started = reltime()
  call assert_equal(1, s:wait_ready(20000), 'PHP language server did not initialize')
  call add(s:report, 'server_ready_ms=' . string(reltimefloat(reltime(s:started)) * 1000))
  if !empty($VIM_CONFIG_LSP_DEBUG) | LspServer debug on | endif
  " Server initialization is distinct from background workspace indexing.
  sleep 200m
  if empty(v:errors)
    let s:call_line = search('return $greeter->greet', 'w')
    call cursor(s:call_line, match(getline(s:call_line), '->\zsgreet') + 4)
    let s:started = reltime()
    let s:startcol = g:LspOmniFunc(1, '')
    call assert_true(s:startcol >= 0, 'completion findstart failed')
    let s:wait = reltime()
    while g:LspOmniCompletePending() && reltimefloat(reltime(s:wait)) < 5
      sleep 10m
    endwhile
    call assert_false(g:LspOmniCompletePending(), 'completion request timed out')
    let s:matches = g:LspOmniFunc(0, 'gre')
    call assert_true(type(s:matches) == v:t_list && !empty(filter(copy(s:matches), 'get(v:val, "word", "") =~# "^greet"')), 'method completion did not include greet: ' . string(s:matches))
    call add(s:report, 'completion_ms=' . string(reltimefloat(reltime(s:started)) * 1000))
    call cursor(s:call_line, match(getline(s:call_line), '->\zsgreet') + 2)
    let s:started = reltime()
    LspGotoDefinition
    call assert_equal(s:temp . '/src/Greeter.php', expand('%:p'), 'definition did not enter Greeter.php')
    call assert_match('function greet', getline('.'), 'definition did not select greet')
    call add(s:report, 'definition_ms=' . string(reltimefloat(reltime(s:started)) * 1000))
    let s:started = reltime()
    LspIncomingCalls
    call assert_equal('LSP-CallHierarchy', bufname('%'), 'incoming calls did not open hierarchy')
    call assert_match('vim_config_fixture_caller', join(getline(1, '$'), "\n"), 'incoming calls omitted known caller')
    call add(s:report, 'incoming_calls_ms=' . string(reltimefloat(reltime(s:started)) * 1000))
    call add(s:report, 'incoming_calls=' . join(getline(1, '$'), ' | '))
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
finally
  if exists('*g:LspDisable') | call g:LspDisable() | endif
  call delete(s:temp, 'rf')
endtry
let s:output = empty($VIM_CONFIG_LSP_TEST_REPORT) ? s:repo . '/.state/lsp-client-test.txt' : $VIM_CONFIG_LSP_TEST_REPORT
call writefile(s:report + v:errors, s:output)
if !empty(v:errors)
  cquit
endif
qa!
