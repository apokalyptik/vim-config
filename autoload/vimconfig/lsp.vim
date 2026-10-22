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
    call add(l:servers, vimconfig#lsp#server('typescript', ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'], [], ['tsconfig.json', 'jsconfig.json', 'package.json', '.git/'],
          \ {'disableAutomaticTypingAcquisition': v:true, 'preferences': {'includeCompletionsForModuleExports': v:false}}, {}))
    call add(l:servers, vimconfig#lsp#server('html', ['html'], [], ['package.json', '.git/'], {'provideFormatter': v:true}, {'html': {'autoClosingTags': v:false, 'autoCreateQuotes': v:false}}))
    call add(l:servers, vimconfig#lsp#server('css', ['css', 'scss', 'less'], [], ['package.json', '.git/'], {'provideFormatter': v:true}, {}))
    call add(l:servers, vimconfig#lsp#server('json', ['json', 'jsonc'], [], ['package.json', '.git/'], {'handledSchemaProtocols': ['file'], 'provideFormatter': v:true}, {'json': {'validate': {'enable': v:true}}}))
  endif
  if executable(vimconfig#tool('gopls'))
    call add(l:servers, vimconfig#lsp#server('go', ['go'], [], ['go.work', 'go.mod', '.git/'], {},
          \ {'gopls': {'directoryFilters': ['-**/node_modules', '-**/wp-content/blogs.dir'], 'semanticTokens': v:false, 'staticcheck': v:false}}))
  endif
  return l:servers
endfunction
