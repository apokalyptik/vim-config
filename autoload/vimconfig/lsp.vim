function! vimconfig#lsp#server(name, filetypes, args, roots, init, config) abort
  return {'name': a:name, 'filetype': a:filetypes,
        \ 'path': vimconfig#root() . '/bin/language-server',
        \ 'args': [a:name] + a:args, 'rootSearch': a:roots,
        \ 'initializationOptions': a:init, 'workspaceConfig': a:config}
endfunction

function! vimconfig#lsp#servers() abort
  if get(g:, 'vimconfig_no_lsp', 0) | return [] | endif
  let l:servers = []
  if executable(vimconfig#tool('phpantom_lsp'))
    call add(l:servers, vimconfig#lsp#server('php', ['php'], [], ['composer.json', '.git/', '.svn/', 'wp-config.php'],
          \ {'indexing': {'exclude': ['**/wp-content/blogs.dir/**'], 'strategy': 'full'}, 'diagnostics': {'workspace': v:false}}, {}))
  endif
  if executable(vimconfig#tool('node'))
    let l:typescript_init = {'disableAutomaticTypingAcquisition': v:true, 'preferences': {'includeCompletionsForModuleExports': v:false}}
    if vimconfig#profile() ==# 'container'
      " One semantic tsserver retains completion/navigation without a separate
      " syntax-only child consuming this session's small process allowance.
      let l:typescript_init.tsserver = {'useSyntaxServer': 'never'}
    endif
    call add(l:servers, vimconfig#lsp#server('typescript', ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'], [], ['tsconfig.json', 'jsconfig.json', 'package.json', '.git/'],
          \ l:typescript_init, {}))
    call add(l:servers, vimconfig#lsp#server('html', ['html'], [], ['package.json', '.git/'], {'provideFormatter': v:true}, {'html': {'autoClosingTags': v:false, 'autoCreateQuotes': v:false}}))
    call add(l:servers, vimconfig#lsp#server('css', ['css', 'scss', 'less'], [], ['package.json', '.git/'], {'provideFormatter': v:true}, {}))
    call add(l:servers, vimconfig#lsp#server('json', ['json', 'jsonc'], [], ['package.json', '.git/'], {'handledSchemaProtocols': ['file'], 'provideFormatter': v:true}, {'json': {'validate': {'enable': v:true}}}))
  endif
  if executable(vimconfig#tool('gopls'))
    let l:go_config = {'directoryFilters': ['-**/node_modules', '-**/wp-content/blogs.dir'], 'semanticTokens': v:false, 'staticcheck': v:false}
    if vimconfig#profile() ==# 'container'
      " A saved vulnerability-scan prompt choice must not start another Go
      " program in the container's shared process/thread allowance.
      let l:go_config.vulncheck = 'Off'
    endif
    call add(l:servers, vimconfig#lsp#server('go', ['go'], [], ['go.work', 'go.mod', '.git/'], {},
          \ {'gopls': l:go_config}))
  endif
  return l:servers
endfunction
