" Data file helpers: highlighting is cheap; validation and queries are explicit.
let s:query_serial = 0

function! s:warn(message) abort
  echohl WarningMsg
  echomsg 'Vim Config: ' . a:message
  echohl None
endfunction

function! vimconfig#data#setup() abort
  let g:disable_rainbow_csv_autodetect = 1
  let g:disable_rainbow_hover = 1
  " Its default Syntax handler probes <table>.header and its BufEnter handler
  " consults a home-directory registry. Our explicit dialects need neither.
  augroup RainbowInitAuGrp
    autocmd!
  augroup END
  if exists(':CSVLint')
    call rainbow_csv#init_rb_color_groups()
  endif
  " Route all advertised query entry points through the guarded launcher.
  command! RainbowQuery call vimconfig#data#query()
  command! RbSelect call vimconfig#data#query()
  command! RbRun call vimconfig#data#run_query()
  command! -nargs=+ Select call vimconfig#data#query('SELECT ' . <q-args>)
  command! -nargs=+ Update call vimconfig#data#query('UPDATE ' . <q-args>)
  augroup VimConfigData
    autocmd!
    autocmd BufEnter,FileType,Syntax * call vimconfig#data#buffer_setup()
  augroup END
  call vimconfig#data#buffer_setup()
endfunction

function! vimconfig#data#buffer_setup() abort
  let b:rbcsv = index(['csv', 'tsv', 'csv_semicolon', 'csv_pipe', 'csv_whitespace', 'rfc_csv', 'rfc_semicolon'], &l:syntax) >= 0
  " Rainbow CSV installs abbreviations which replace the entire statusline.
  " Keep its syntax and linting while leaving our common statusline in charge.
  if get(b:, 'rbcsv', 0)
    for abbreviation in ['Select', 'select', 'SELECT', 'Update', 'update', 'UPDATE']
      if !empty(maparg(abbreviation, 'c', 1))
        execute 'silent! cunabbrev <buffer> ' . abbreviation
      endif
    endfor
  endif
  if exists('g:vimconfig_statusline')
    let &g:statusline = g:vimconfig_statusline
    let &l:statusline = g:vimconfig_statusline
  endif
endfunction

function! s:dialect() abort
  if !exists(':CSVLint')
    return []
  endif
  let dialect = rainbow_csv#get_current_dialect()
  return dialect[1] ==# 'monocolumn' ? [] : dialect
endfunction

function! vimconfig#data#validate() abort
  let dialect = s:dialect()
  if empty(dialect)
    call s:warn('Choose a CSV/TSV delimiter first.')
    return
  endif
  if dialect[1] ==# 'quoted_rfc'
    call s:warn('Rainbow CSV lint does not yet support multiline quoted fields. A SELECT * query validates their parsing.')
    return
  endif
  " Upstream lint operates only on the current in-memory buffer.
  CSVLint
endfunction

function! s:set_dialect(filetype) abort
  let &l:filetype = a:filetype
  let &l:syntax = &l:filetype
  call vimconfig#data#buffer_setup()
endfunction

function! vimconfig#data#choose_delimiter() abort
  if !exists(':CSVLint')
    call s:warn('The bundled Rainbow CSV plugin is unavailable.')
    return
  endif
  let formats = [
        \ ['CSV: comma, quoted fields', 'csv'],
        \ ['TSV: tab-separated', 'tsv'],
        \ ['Semicolon, quoted fields', 'csv_semicolon'],
        \ ['Pipe-separated', 'csv_pipe'],
        \ ['CSV with multiline quoted fields', 'rfc_csv'],
        \ ['Semicolon with multiline quoted fields', 'rfc_semicolon'],
        \ ['Plain text: disable table highlighting', 'text']]
  let items = []
  for [label, filetype] in formats
    call add(items, {'label': label, 'action': function('s:set_dialect', [filetype])})
  endfor
  call vimconfig#ui#choose('Table format', items)
endfunction

function! vimconfig#data#status() abort
  if &filetype ==# 'serversdat' && exists('*ServersdatCurrentColumnName')
    let parts = [ServersdatCurrentColumnName(), ServersdatCurrentColumnSubName()]
    if strlen(getline('.')) <= 4096 && exists('*ServersDatCurrentHostname')
      call insert(parts, ServersDatCurrentHostname())
    endif
    return join(filter(parts, '!empty(v:val)'), ' › ')
  endif
  if !get(b:, 'rbcsv', 0)
    return ''
  endif
  " Bound status work for wide rows. Byte slicing matches Vim's col() units.
  let pos = col('.') - 1
  if pos > 4096
    return 'Table'
  endif
  let dialect = s:dialect()
  if empty(dialect)
    return ''
  endif
  let prefix = strpart(getline('.'), 0, pos)
  let fields = rainbow_csv#preserving_smart_split(prefix, dialect[0], dialect[1])[0]
  return 'Col ' . max([1, len(fields)])
endfunction

function! vimconfig#data#query(...) abort
  if get(b:, 'vimconfig_query_draft', 0)
    call vimconfig#data#run_query()
    return
  endif
  let dialect = s:dialect()
  if empty(dialect)
    call s:warn('Choose a CSV/TSV delimiter before querying.')
    return
  endif
  let file = expand('%:p')
  if !empty(file) && !vimconfig#path_allowed(file)
    call s:warn('This table is excluded.')
    return
  endif
  let source = bufnr('%')
  let cwd = empty(file) ? getcwd() : fnamemodify(file, ':h')
  let s:query_serial += 1
  botright 8new
  execute 'file ' . fnameescape('[Table query ' . s:query_serial . ']')
  setlocal buftype=nofile bufhidden=hide noswapfile filetype=javascript
  let b:vimconfig_query_draft = 1
  let b:vimconfig_query_source = source
  let b:vimconfig_query_dialect = dialect
  let b:vimconfig_query_cwd = cwd
  call setline(1, [a:0 ? a:1 : 'SELECT *', '',
        \ '// JavaScript expressions: SELECT a1, a2 WHERE a1.length > 3',
        \ '// F1 → Run table query executes against an in-memory snapshot.',
        \ '// Results open separately. The original table is never replaced.'])
  call cursor(1, 1)
  startinsert
endfunction

function! s:query_output(state, channel, message) abort
  call add(a:state.output, a:message)
endfunction

function! s:query_error(state, channel, message) abort
  call add(a:state.errors, a:message)
endfunction

function! s:query_close(state, channel) abort
  " close_cb runs after all stdout/err callbacks, unlike exit_cb.
  call delete(a:state.table)
  call delete(a:state.script)
  if empty(a:state.output) || a:state.output[0] !=# 'OK'
    call delete(a:state.result)
    let message = join(a:state.output + a:state.errors, ' ')
    call s:warn('Table query failed: ' . (empty(message) ? 'no result returned' : message))
    return
  endif
  let result = get(a:state.output, 1, '')
  if result !=# a:state.result
    call delete(a:state.result)
    call s:warn('Table query returned an unexpected result path.')
    return
  endif
  if empty(result) || !vimconfig#path_allowed(result) || !filereadable(result)
    call s:warn('Table query returned an unavailable or excluded result path.')
    return
  endif
  " Leave large results on disk rather than synchronously reading them here.
  execute 'botright split ' . fnameescape(result)
  let &l:filetype = a:state.filetype
  let &l:syntax = &l:filetype
  let b:vimconfig_query_result = 1
  if len(a:state.output) > 2
    echomsg 'Table query: ' . join(a:state.output[2:], ' ')
  endif
endfunction

function! vimconfig#data#run_query() abort
  if !get(b:, 'vimconfig_query_draft', 0)
    call s:warn('Open a table query draft first.')
    return
  endif
  let source = b:vimconfig_query_source
  if !bufexists(source) || !bufloaded(source)
    call s:warn('The source table buffer was closed.')
    return
  endif
  let node = vimconfig#tool('node')
  let engines = globpath(&runtimepath, 'rbql_core/rbql-js/rbql_csv.js', 0, 1)
  if empty(node) || !executable(node) || empty(engines)
    call s:warn('The bundled Node runtime and Rainbow CSV RBQL engine are required.')
    return
  endif
  let source_path = fnamemodify(bufname(source), ':p')
  if (!empty(bufname(source)) && !vimconfig#path_allowed(source_path)) || !vimconfig#path_allowed(b:vimconfig_query_cwd)
    call s:warn('The table or query directory is excluded.')
    return
  endif
  let query = filter(getline(1, '$'), 'v:val !~# "^\\s*//"')
  if empty(substitute(join(query, ''), '\s', '', 'g'))
    call s:warn('The query is empty.')
    return
  endif
  let table = tempname()
  let script = tempname()
  let result = tempname() . '.csv'
  call writefile(getbufline(source, 1, '$'), table)
  call writefile(query, script)
  call writefile([], result)
  call setfperm(table, 'rw-------')
  call setfperm(script, 'rw-------')
  call setfperm(result, 'rw-------')
  let dialect = b:vimconfig_query_dialect
  let state = {'output': [], 'errors': [], 'table': table, 'script': script, 'result': result,
        \ 'filetype': getbufvar(source, '&filetype')}
  " Use the engine API with an explicit, private output path. The upstream
  " vim_rbql.js wrapper writes a basename-derived file in shared /tmp.
  let js = 'const [engine,input,output,script,delim,policy,header,comment]=process.argv.slice(1);'
        \ . 'const fs=require("fs"),warnings=[];'
        \ . 'require(engine).query_csv(fs.readFileSync(script,"utf8"),input,delim,policy,output,delim,policy,"utf-8",warnings,header==="1",comment,"",{trim_whitespaces:false})'
        \ . '.then(()=>{console.log("OK");console.log(output);warnings.forEach(w=>console.log(w));})'
        \ . '.catch(e=>{console.error(e.message);process.exitCode=1;});'
  let argv = [node, '-e', js, engines[0], table, result, script, dialect[0], dialect[1],
        \ get(g:, 'rbql_with_headers', 0) ? '1' : '0', dialect[2]]
  try
    let job = vimconfig#job(argv, {'cwd': b:vimconfig_query_cwd,
          \ 'out_mode': 'nl', 'err_mode': 'nl',
          \ 'out_cb': function('s:query_output', [state]),
          \ 'err_cb': function('s:query_error', [state]),
          \ 'close_cb': function('s:query_close', [state])})
    if job_status(job) ==# 'fail'
      throw 'Could not start the table query helper.'
    endif
    let b:vimconfig_query_job = job
    echomsg 'Table query running…'
  catch
    call delete(table)
    call delete(script)
    call delete(result)
    call s:warn(v:exception)
  endtry
endfunction

function! vimconfig#data#actions() abort
  return [
        \ {'label': 'Table: Validate CSV/TSV', 'action': function('vimconfig#data#validate')},
        \ {'label': 'Table: Choose delimiter/format', 'action': function('vimconfig#data#choose_delimiter')},
        \ {'label': 'Table: Write query (JavaScript RBQL)', 'action': function('vimconfig#data#query')},
        \ {'label': 'Table: Run query', 'action': function('vimconfig#data#run_query')}]
endfunction
