# Downstream: container family lifecycle. Inserted into the pinned LSP module.
var vimConfigFamilySwitching = false
var vimConfigFamilyClosing: dict<bool> = {}

def VimConfigJobAlive(server: dict<any>): bool
  return type(server.job) == v:t_job && job_status(server.job) == 'run'
enddef

def VimConfigUniqueServers(): list<dict<any>>
  var seen: dict<bool> = {}
  var result: list<dict<any>> = []
  for servers in ftypeServerMap->values()
    for server in servers
      var key = string(server.id)
      if !seen->has_key(key)
        seen[key] = true
        result->add(server)
      endif
    endfor
  endfor
  return result
enddef

def VimConfigShutdownReply(server: dict<any>, result: any, error: dict<any>)
  try
    server.exitServer()
  catch
    # A concurrent clean exit can close the channel between these messages.
  endtry
  try
    server.vimConfigInputClosed = true
    ch_close_in(job_getchannel(server.job))
  catch
    # Closing stdin after exit is graceful EOF, including a concurrent exit.
  endtry
enddef

def VimConfigShutdownForJob(stoppingJob: job, server: dict<any>, result: any, error: dict<any>)
  # A late response from a retired channel must never stop a new instance.
  if server.job == stoppingJob && job_status(stoppingJob) == 'run'
    VimConfigShutdownReply(server, result, error)
  endif
enddef

def VimConfigGracefulStop(server: dict<any>)
  var key = string(server.id)
  if !VimConfigJobAlive(server)
    server.running = false
    server.ready = false
    if vimConfigFamilyClosing->has_key(key)
      vimConfigFamilyClosing->remove(key)
    endif
    return
  endif
  if vimConfigFamilyClosing->has_key(key)
    return
  endif
  vimConfigFamilyClosing[key] = true
  # Detach without writing or unloading buffers. didOpen on reactivation uses
  # the current in-memory contents, including all unsaved changes.
  for info in getbufinfo()
    if buf.BufLspServersGet(info.bufnr)->copy()->filter((_, item) => item.id == server.id)->len() > 0
      RemoveFile(info.bufnr)
    endif
  endfor
  try
    # Keep processing server requests while awaiting shutdown. In particular,
    # PHP can await workDoneProgress/create replies during initial indexing.
    server.rpc_a('shutdown', v:null, function(VimConfigShutdownForJob, [server.job]))
  catch
    # A failed request does not justify force-terminating a live family.
  endtry
enddef

def VimConfigStopped(server: dict<any>)
  if server.diagnosticPullTimer != -1
    timer_stop(server.diagnosticPullTimer)
    server.diagnosticPullTimer = -1
  endif
  server.pendingPullBufnrs = {}
  server.running = false
  server.ready = false
enddef

def VimConfigPhpTerm(server: dict<any>): bool
  # The bundled PHP indexer is one process with worker threads. Its stdio
  # shutdown can acknowledge and then hang. Only this known launcher may use
  # the normal upstream TERM fallback; never force-kill or overlap families.
  if server.name != 'php' || server.path != get(g:, 'vimconfig_root', '') .. '/bin/language-server'
      || get(server.args, 0, '') != 'php' || get(server, 'vimConfigPhpTermSent', false)
    return false
  endif
  server.vimConfigPhpTermSent = true
  VimConfigShutdownReply(server, v:null, {})
  return job_stop(server.job, 'term')
enddef

def VimConfigReattachFamily(bnr: number, desired: list<dict<any>>)
  if get(g:, 'vimconfig_profile', '') != 'container' || bnr != bufnr()
    return
  endif
  var wanted = desired->copy()->map((_, server) => server.id)
  for info in getbufinfo({'bufloaded': 1})
    if info.bufnr == bnr
      continue
    endif
    var servers = ftypeServerMap->get(getbufvar(info.bufnr, '&filetype'), [])
    if !servers->empty() && wanted->index(servers[0].id) >= 0
      AddFile(info.bufnr)
    endif
  endfor
enddef

def VimConfigSelectFamily(bnr: number, desired: list<dict<any>>): bool
  if get(g:, 'vimconfig_profile', '') != 'container'
    return true
  endif
  if vimConfigFamilySwitching
    return false
  endif
  # Hidden-buffer events must not switch the user's active language family.
  if bnr != bufnr()
    var current = ftypeServerMap->get(&filetype, [])
    return !desired->empty() && desired[0]->get('id', -1) == get(get(current, 0, {}), 'id', -2)
  endif
  var wanted = desired->copy()->map((_, server) => server.id)
  var servers = VimConfigUniqueServers()
  for server in servers
    var key = string(server.id)
    if !VimConfigJobAlive(server) && vimConfigFamilyClosing->has_key(key)
      vimConfigFamilyClosing->remove(key)
    endif
  endfor
  var old = servers->filter((_, server) => (wanted->index(server.id) < 0 || vimConfigFamilyClosing->has_key(string(server.id))) && VimConfigJobAlive(server))
  if old->empty()
    return true
  endif
  vimConfigFamilySwitching = true
  try
    for server in old
      VimConfigGracefulStop(server)
    endfor
    var started = reltime()
    while old->copy()->filter((_, server) => VimConfigJobAlive(server))->len() > 0
      if reltimefloat(reltime(started)) >= get(g:, 'vimconfig_family_stop_timeout', 2.0)
        var signaled = false
        for server in old
          if VimConfigJobAlive(server) && VimConfigPhpTerm(server)
            signaled = true
          endif
        endfor
        if signaled
          started = reltime()
          continue
        endif
        util.WarnMsg('Previous language server is still stopping; this family was not started. Re-enter the buffer to retry.')
        return false
      endif
      sleep 10m
    endwhile
    for server in old
      VimConfigStopped(server)
      var key = string(server.id)
      if vimConfigFamilyClosing->has_key(key)
        vimConfigFamilyClosing->remove(key)
      endif
    endfor
    return true
  finally
    vimConfigFamilySwitching = false
  endtry
  return false
enddef

export def VimConfigContainerStop(server: dict<any>): bool
  VimConfigGracefulStop(server)
  var started = reltime()
  while VimConfigJobAlive(server)
    if reltimefloat(reltime(started)) >= get(g:, 'vimconfig_family_stop_timeout', 2.0)
      if VimConfigPhpTerm(server)
        started = reltime()
        continue
      endif
      return false
    endif
    sleep 10m
  endwhile
  VimConfigStopped(server)
  var key = string(server.id)
  if vimConfigFamilyClosing->has_key(key)
    vimConfigFamilyClosing->remove(key)
  endif
  return true
enddef
