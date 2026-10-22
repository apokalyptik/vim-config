" Run: vim -Nu NONE -i NONE -n -es -S tests/test-vcs.vim
set nocompatible
set noswapfile
set viminfo=
let s:repo = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:temp = tempname()
call mkdir(s:temp . '/mock/autoload', 'p')
let g:vimconfig_test_calls = []
let g:vimconfig_test_denied = ''
let g:vimconfig_test_profile = empty($VIM_CONFIG_PROFILE) ? 'misc' : $VIM_CONFIG_PROFILE
call writefile([
      \ 'function! vimconfig#profile() abort',
      \ '  return g:vimconfig_test_profile',
      \ 'endfunction',
      \ 'function! vimconfig#path_allowed(path) abort',
      \ '  return empty(g:vimconfig_test_denied) || stridx(a:path, g:vimconfig_test_denied) != 0',
      \ 'endfunction',
      \ 'function! vimconfig#job(argv, opts) abort',
      \ '  call add(g:vimconfig_test_calls, {"argv": copy(a:argv), "opts": copy(a:opts)})',
      \ '  if get(g:, "vimconfig_test_real_query", 0) | return job_start(a:argv, a:opts) | endif',
      \ '  return job_start(["printf", "fake-output\n"], a:opts)',
      \ 'endfunction',
      \ 'function! vimconfig#tool(name) abort',
      \ '  return exepath(a:name)',
      \ 'endfunction'], s:temp . '/mock/autoload/vimconfig.vim')
let &runtimepath = s:temp . '/mock,' . s:repo . ',' . s:repo . '/vendor/pack/vim-config/start/rainbow_csv,' . $VIMRUNTIME
let g:disable_rainbow_csv_autodetect = 1
let g:disable_rainbow_hover = 1
let g:vimconfig_statusline = '%f %m'
runtime plugin/rainbow_csv.vim
call vimconfig#data#setup()
syntax enable

try
  let s:tree = s:temp . '/working tree'
  call mkdir(s:tree . '/.git', 'p')
  let s:file = s:tree . '/literal ; $special.php'
  call writefile(['<?php echo 1;'], s:file)
  execute 'edit ' . fnameescape(s:file)
  call vimconfig#vcs#status()
  call assert_equal('git', g:vimconfig_test_calls[-1].argv[0])
  call assert_equal(s:tree, g:vimconfig_test_calls[-1].opts.cwd)
  call assert_true(index(g:vimconfig_test_calls[-1].argv, '--untracked-files=normal') >= 0)
  call assert_equal(g:vimconfig_test_profile ==# 'container', index(g:vimconfig_test_calls[-1].argv, 'index.threads=1') >= 0)
  call assert_equal(g:vimconfig_test_profile ==# 'container', index(g:vimconfig_test_calls[-1].argv, 'maintenance.auto=false') >= 0)
  call assert_equal(v:t_func, type(g:vimconfig_test_calls[-1].opts.out_cb))

  " A scratch view retains the source repository and exact file argument.
  call vimconfig#vcs#diff()
  call assert_equal(['--', 'literal ; $special.php'], g:vimconfig_test_calls[-1].argv[-2:])
  call assert_true(index(g:vimconfig_test_calls[-1].argv, '--no-ext-diff') >= 0)
  call assert_true(index(g:vimconfig_test_calls[-1].argv, '--no-textconv') >= 0)

  " Guard denial must stop dispatch, including from an existing VCS view.
  let s:count = len(g:vimconfig_test_calls)
  let g:vimconfig_test_denied = s:tree
  call vimconfig#vcs#log()
  call assert_equal(s:count, len(g:vimconfig_test_calls))
  let g:vimconfig_test_denied = ''

  call vimconfig#vcs#commit()
  stopinsert
  call assert_true(get(b:, 'vimconfig_commit_draft', 0))
  call vimconfig#vcs#submit_commit()
  call assert_equal(s:count, len(g:vimconfig_test_calls), 'empty draft must not submit')
  call setline(1, 'A literal message $(touch /tmp/never)')
  call vimconfig#vcs#submit_commit()
  let s:commit = g:vimconfig_test_calls[-1].argv
  call assert_equal('commit', s:commit[-3])
  call assert_equal('--file', s:commit[-2])
  call assert_equal('A literal message $(touch /tmp/never)', readfile(s:commit[-1])[0])
  call assert_equal(s:count + 1, len(g:vimconfig_test_calls))

  " SVN @-escaping must keep filenames with peg-like suffixes literal.
  call mkdir(s:temp . '/svn/.svn', 'p')
  let s:svnfile = s:temp . '/svn/data@42.php'
  call writefile(['<?php'], s:svnfile)
  execute 'edit ' . fnameescape(s:svnfile)
  call vimconfig#vcs#diff()
  call assert_equal(['svn', '--non-interactive', 'diff', '--internal-diff', '--', 'data@42.php@'], g:vimconfig_test_calls[-1].argv)

  " The data status helper is bounded and must not replace our statusline.
  enew
  call setline(1, 'name,value,comment')
  setlocal filetype=csv syntax=csv
  call vimconfig#data#buffer_setup()
  call cursor(1, 7)
  call assert_equal('Col 2', vimconfig#data#status())
  call assert_equal(g:vimconfig_statusline, &statusline)
  call assert_equal('', maparg('select', 'c', 1))
  call assert_match('vimconfig#data#query', execute('command RainbowQuery'))
  call vimconfig#data#query()
  call assert_true(get(b:, 'vimconfig_query_draft', 0))
  call assert_equal('SELECT *', getline(1))
  if executable('node')
    let g:vimconfig_test_real_query = 1
    call setline(1, 'SELECT a2')
    call vimconfig#data#run_query()
    let s:query_job = b:vimconfig_query_job
    let s:query_argv = g:vimconfig_test_calls[-1].argv
    let s:waited = 0
    while job_status(s:query_job) ==# 'run' && s:waited < 5000
      sleep 10m
      let s:waited += 10
    endwhile
    sleep 20m
    call assert_equal(0, job_info(s:query_job).exitval)
    call assert_true(get(b:, 'vimconfig_query_result', 0))
    call assert_equal('value', getline(1))
    call assert_equal('rw-------', getfperm(expand('%:p')))
    call assert_equal(0, filereadable(s:query_argv[4]), 'query input snapshot must be cleaned')
    call assert_equal(0, filereadable(s:query_argv[6]), 'query script snapshot must be cleaned')
    let g:vimconfig_test_real_query = 0
  endif
  call assert_true(len(vimconfig#vcs#actions()) >= 6)
  call assert_equal(4, len(vimconfig#data#actions()))

  " Let asynchronous completion callbacks drain before removing fixtures.
  sleep 100m
  call assert_equal(0, filereadable(s:commit[-1]), 'commit message temp must be cleaned')
finally
  call delete(s:temp, 'rf')
endtry

if !empty(v:errors)
  call writefile(v:errors, '/tmp/vim-config-vcs-test-errors')
  cquit
endif
qa!
