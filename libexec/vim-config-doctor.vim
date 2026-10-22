" Run with -Nu NONE -i NONE -n -es. Requires no Python on the destination.
set nomore
let s:report = []
let s:failed = 0
let s:root = $VIM_DOCTOR_ROOT
let s:temp = $VIM_DOCTOR_TEMP
let s:tools = s:root . '/.state/tools/' . $VIM_DOCTOR_PLATFORM
let s:env = {
      \ 'XDG_CACHE_HOME': s:temp . '/cache',
      \ 'XDG_CONFIG_HOME': s:temp . '/config',
      \ 'GOCACHE': s:temp . '/gocache',
      \ 'GOMODCACHE': s:temp . '/gomodcache',
      \ 'GOPATH': s:temp . '/gopath',
      \ 'GOROOT': s:tools . '/go',
      \ 'GOTOOLCHAIN': 'local', 'GOPROXY': 'off', 'GOSUMDB': 'off',
      \ 'GOTELEMETRY': 'off', 'GOTELEMETRYDIR': s:temp . '/telemetry',
      \ 'PATH': s:tools . '/go/bin:' . s:tools . '/bin:' . $PATH,
      \ }
call mkdir(s:temp . '/project', 'p')
call writefile(['module doctor.invalid/probe', '', 'go 1.23'], s:temp . '/project/go.mod')
call writefile(['package probe', 'import "fmt"', 'func Example() { fmt.Println("fixture") }'], s:temp . '/project/probe.go')
call writefile(['<?php', 'function fixture_name(): string { return "fixture"; }', 'fixture_name();'], s:temp . '/project/probe.php')
let s:uri = 'file://' . substitute(s:temp . '/project', ' ', '%20', 'g')

function! s:Log(ok, message) abort
  call add(s:report, (a:ok ? 'PASS: ' : 'FAIL: ') . a:message)
  if !a:ok | let s:failed = 1 | endif
endfunction

function! s:Send(state, value) abort
  let l:body = json_encode(a:value)
  call ch_sendraw(job_getchannel(a:state.job), 'Content-Length: ' . strlen(l:body) . "\r\n\r\n" . l:body)
endfunction

function! s:Output(state, channel, chunk) abort
  let a:state.buffer .= a:chunk
  while 1
    let l:end = stridx(a:state.buffer, "\r\n\r\n")
    if l:end < 0 | return | endif
    let l:length = matchstr(strpart(a:state.buffer, 0, l:end), '\cContent-Length:\s*\zs\d\+')
    if empty(l:length) | let a:state.error = 'invalid LSP framing' | return | endif
    let l:length = str2nr(l:length)
    if strlen(a:state.buffer) < l:end + 4 + l:length | return | endif
    try
      let l:message = json_decode(strpart(a:state.buffer, l:end + 4, l:length))
      let a:state.buffer = strpart(a:state.buffer, l:end + 4 + l:length)
      if has_key(l:message, 'id') && !has_key(l:message, 'method')
        let a:state.responses[string(l:message.id)] = l:message
      elseif has_key(l:message, 'id')
        let l:result = v:null
        if l:message.method ==# 'workspace/configuration'
          let l:result = map(copy(get(get(l:message, 'params', {}), 'items', [])), '{}')
        elseif l:message.method ==# 'workspace/workspaceFolders'
          let l:result = [{'uri': s:uri, 'name': 'doctor-fixture'}]
        elseif l:message.method ==# 'workspace/applyEdit'
          let l:result = {'applied': v:false}
        endif
        call s:Send(a:state, {'jsonrpc': '2.0', 'id': l:message.id, 'result': l:result})
      endif
    catch
      let a:state.error = v:exception
      return
    endtry
  endwhile
endfunction

function! s:Error(state, channel, chunk) abort
  " Keep fixture-only stderr bounded. It is not printed or persisted on success.
  let a:state.stderr = strpart(a:state.stderr . a:chunk, 0, 8192)
endfunction

function! s:Start(command) abort
  let l:state = {'buffer': '', 'stderr': '', 'error': '', 'responses': {}}
  let l:argv = [s:root . '/bin/helper-run', '--profile', $VIM_DOCTOR_PROFILE, '--'] + a:command
  let l:state.job = job_start(l:argv, {'cwd': s:temp . '/project', 'env': s:env,
        \ 'in_mode': 'raw', 'out_mode': 'raw', 'err_mode': 'raw',
        \ 'out_cb': function('s:Output', [l:state]), 'err_cb': function('s:Error', [l:state])})
  return l:state
endfunction

function! s:Stop(state) abort
  if job_status(a:state.job) !=# 'run' | return | endif
  call job_stop(a:state.job, 'term')
  let l:start = reltime()
  while job_status(a:state.job) ==# 'run' && reltimefloat(reltime(l:start)) < 1
    sleep 10m
  endwhile
  if job_status(a:state.job) ==# 'run' | call job_stop(a:state.job, 'kill') | endif
endfunction

function! s:Wait(state, id, seconds) abort
  let l:start = reltime()
  while reltimefloat(reltime(l:start)) < a:seconds
    if has_key(a:state.responses, string(a:id))
      return a:state.responses[string(a:id)]
    endif
    if !empty(a:state.error) || job_status(a:state.job) !=# 'run' | break | endif
    sleep 10m
  endwhile
  return {}
endfunction

function! s:Version(label, command) abort
  let l:state = {'buffer': '', 'stderr': '', 'error': '', 'responses': {}}
  let l:argv = [s:root . '/bin/helper-run', '--profile', $VIM_DOCTOR_PROFILE, '--'] + a:command
  let l:state.job = job_start(l:argv, {'cwd': s:temp, 'env': s:env,
        \ 'out_mode': 'raw', 'err_mode': 'raw',
        \ 'out_cb': {channel, chunk -> extend(l:state, {'buffer': l:state.buffer . chunk})},
        \ 'err_cb': function('s:Error', [l:state])})
  let l:start = reltime()
  while job_status(l:state.job) ==# 'run' && reltimefloat(reltime(l:start)) < 10
    sleep 10m
  endwhile
  let l:status = job_status(l:state.job)
  if l:status ==# 'run' | call s:Stop(l:state) | endif
  let l:ok = l:status ==# 'dead' && get(job_info(l:state.job), 'exitval', -1) == 0
  let l:line = get(split(l:state.buffer, "\n"), 0, '')
  call s:Log(l:ok, a:label . (l:ok ? ' — ' . strpart(l:line, 0, 140) : ' could not start (or timed out)'))
  if !l:ok && !empty(l:state.stderr)
    call add(s:report, '  ' . strpart(substitute(l:state.stderr, '[\r\n]', ' ', 'g'), 0, 200))
  endif
endfunction

function! s:Lsp(label, command, language, file) abort
  let l:state = s:Start(a:command)
  try
    call s:Send(l:state, {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
          \ 'processId': v:null, 'rootUri': s:uri, 'capabilities': {},
          \ 'workspaceFolders': [{'uri': s:uri, 'name': 'doctor-fixture'}]}})
    let l:response = s:Wait(l:state, 1, 25)
    let l:ok = has_key(l:response, 'result') && !has_key(l:response, 'error')
    call s:Log(l:ok, a:label . ' LSP initialize in a temporary workspace')
    if !l:ok | return | endif
    call s:Send(l:state, {'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})
    let l:file_uri = s:uri . '/' . a:file
    let l:text = join(readfile(s:temp . '/project/' . a:file), "\n") . "\n"
    call s:Send(l:state, {'jsonrpc': '2.0', 'method': 'textDocument/didOpen', 'params': {'textDocument': {
          \ 'uri': l:file_uri, 'languageId': a:language, 'version': 1, 'text': l:text}}})
    let l:position = a:language ==# 'go' ? {'line': 2, 'character': 22} : {'line': 2, 'character': 4}
    call s:Send(l:state, {'jsonrpc': '2.0', 'id': 2, 'method': 'textDocument/definition',
          \ 'params': {'textDocument': {'uri': l:file_uri}, 'position': l:position}})
    let l:definition = s:Wait(l:state, 2, a:language ==# 'go' ? 90 : 20)
    let l:ok = has_key(l:definition, 'result') && !has_key(l:definition, 'error') && !empty(l:definition.result)
    call s:Log(l:ok, a:label . (a:language ==# 'go' ? ' Go standard-library definition (requires functioning Go tooling)' : ' PHP definition'))
    if !l:ok
      call add(s:report, '  Fixture response: ' . strpart(json_encode(l:definition), 0, 500))
      if !empty(l:state.stderr)
        call add(s:report, '  Server stderr: ' . strpart(substitute(l:state.stderr, '[\r\n]', ' ', 'g'), 0, 500))
      endif
    endif
    call s:Send(l:state, {'jsonrpc': '2.0', 'id': 99, 'method': 'shutdown', 'params': v:null})
    call s:Wait(l:state, 99, 2)
    call s:Send(l:state, {'jsonrpc': '2.0', 'method': 'exit', 'params': v:null})
  finally
    call s:Stop(l:state)
  endtry
endfunction

try
  if $VIM_DOCTOR_PROFILE ==# 'sandbox'
    " Check the real wrapper, fresh proc, capability drop, read-only empty mask.
    call s:Version('Sandbox namespace/mount/proc launcher', ['/bin/sh', '-c',
          \ 'test -d /nfs && test -z "$(ls -A /nfs)" && ! touch /nfs/vim-config-probe 2>/dev/null && test "$(awk ''/^CapBnd:/ {print $2}'' /proc/self/status)" = 0000000000000000 && printf "empty /nfs; capabilities dropped\n"'])
  endif
  for [s:label, s:binary, s:arguments] in [
        \ ['Bundled PHPantom', s:tools . '/bin/phpantom_lsp', ['--version']],
        \ ['Bundled Node', s:tools . '/bin/node', ['--eval', 'process.stdout.write(process.version + " JavaScript runtime ready\n")']],
        \ ['Bundled Go SDK', s:tools . '/go/bin/go', ['version']],
        \ ['Bundled gopls', s:tools . '/bin/gopls', ['version']]]
    if executable(s:binary)
      call s:Version(s:label, [s:binary] + s:arguments)
    else
      call s:Log(0, s:label . ' is not staged; run bin/vim-config once to unpack the checked-in payloads')
    endif
  endfor
  if $VIM_DOCTOR_MODE ==# 'lsp'
    if executable(s:tools . '/bin/phpantom_lsp')
      call s:Lsp('PHPantom', [s:tools . '/bin/phpantom_lsp'], 'php', 'probe.php')
    endif
    if executable(s:tools . '/bin/gopls') && executable(s:tools . '/go/bin/go')
      call s:Lsp('gopls', [s:tools . '/bin/gopls'], 'go', 'probe.go')
    endif
  endif
catch
  call s:Log(0, 'doctor probe exception: ' . v:exception)
endtry
call writefile(s:report, s:temp . '/report')
if s:failed | cquit | else | qall! | endif
