#!/usr/bin/env python3
"""Reapply admission, per-buffer, shutdown and PID hooks to the pinned LSP."""
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'vendor/pack/vim-config/start/lsp'
path = root / 'autoload/lsp/lsp.vim'
text = path.read_text()
needle = 'export def AddFile(bnr: number): void\n'
guard = """  # Downstream: apply host exclusions and fast mode before root discovery.
  if exists('*g:VimConfigLspAllow') && !g:VimConfigLspAllow(bnr)
    return
  endif
"""
if guard not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, needle + guard))
text = path.read_text()
lifecycle = (Path(__file__).resolve().parent / 'lsp-container-lifecycle.vim').read_text()
lifecycle_marker = '# Downstream: container family lifecycle.'
if lifecycle_marker in text:
    text = text.split(lifecycle_marker, 1)[0] + lifecycle
else:
    text += '\n' + lifecycle
needle = '  var lspservers: list<dict<any>> = LspGetServers(bnr, ftype)\n'
family_guard = '''  # Downstream: stop the preceding container family before starting another.
  if !VimConfigSelectFamily(bnr, lspservers)
    return
  endif
'''
if family_guard not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + family_guard)
needle = '  var attachedServers: list<dict<any>> = []\n'
started_flag = '  var vimConfigFamilyStarted = false\n'
if started_flag not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + started_flag)
needle = '      lspserver.startServer(bnr)\n'
started_mark = '      vimConfigFamilyStarted = true\n'
if started_mark not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + started_mark)
needle = '\nenddef\n\n# Notify LSP server to remove a file\n'
reattach = '''
  # Downstream: reopen loaded same-family buffers from their in-memory contents.
  if vimConfigFamilyStarted
    VimConfigReattachFamily(bnr, lspservers)
  endif
'''
if reattach not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, reattach + needle)
needle = "    autocmd BufNewFile,BufReadPost,FileType * AddFile(expand('<abuf>')->str2nr())\n"
enter = "    autocmd BufEnter * if get(g:, 'vimconfig_profile', '') == 'container' | AddFile(expand('<abuf>')->str2nr()) | endif\n"
if enter not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + enter)
path.write_text(text)
path = root / 'plugin/lsp.vim'
text = path.read_text()
needle = 'def g:LspDisable()\n  lsp.LspDisable()\nenddef\n'
hooks = """
# Downstream: per-buffer controls keep fast mode local to the chosen file.
def g:VimConfigLspDetach(bnr: number)
  lsp.RemoveFile(bnr)
enddef

def g:VimConfigLspAttach(bnr: number)
  lsp.AddFile(bnr)
enddef
"""
if hooks not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, needle + hooks))
text = path.read_text()
stop_hook = '''
# Downstream: container lifecycle never force-terminates a still-running family.
def g:VimConfigLspStopFamily(server: dict<any>): bool
  return lsp.VimConfigContainerStop(server)
enddef
'''
if stop_hook not in text:
    path.write_text(text + stop_hook)
path = root / 'autoload/lsp/lspserver.vim'
text = path.read_text()
needle = 'def Output_cb(lspserver: dict<any>, chan: channel, msg: any): void\n'
closed_guard = '''  # Downstream: ignore retired-family output after graceful stdin EOF.
  if get(lspserver, 'vimConfigInputClosed', false)
    return
  endif
'''
text = text.replace("  if get(g:, 'vimconfig_profile', '') == 'container' && ch_status(chan, {part: 'in'}) != 'open'\n", "  if get(lspserver, 'vimConfigInputClosed', false)\n")
if closed_guard not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + closed_guard)
path.write_text(text)
needle = "  lspserver.data = ''\n"
input_reset = '  lspserver.vimConfigInputClosed = false\n'
if input_reset not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + input_reset)
path.write_text(text)
needle = input_reset
term_reset = '  lspserver.vimConfigPhpTermSent = false\n'
if term_reset not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + term_reset)
path.write_text(text)
needle = 'def StopServer(lspserver: dict<any>): number\n'
stop_guard = '''  # Downstream: no job_stop fallback while container children may be alive.
  if get(g:, 'vimconfig_profile', '') == 'container' && exists('*g:VimConfigLspStopFamily')
    return g:VimConfigLspStopFamily(lspserver) ? 0 : 1
  endif
'''
if stop_guard not in text:
    assert text.count(needle) == 1
    text = text.replace(needle, needle + stop_guard)
    path.write_text(text)
needle = """def Rpc(lspserver: dict<any>, method: string, params: any, opts: dict<any> = {}): dict<any>
  var req = {
    method: method,
    params: params
  }
"""
fix = """  # Downstream: PHPantom expects shutdown to omit optional params entirely.
  if method == 'shutdown'
    req->remove('params')
  endif
"""
if fix not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, needle + fix))
text = path.read_text()
needle = """def AsyncRpc(lspserver: dict<any>, method: string, params: any, Cbfunc: func): number
  var req = {
    method: method,
    params: params
  }
"""
if fix not in text[text.index('def AsyncRpc('):]:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, needle + fix))
text = path.read_text()
needle = "  notif.params->extend(params)\n"
fix = """  # Downstream: exit has void params; PHPantom expects them omitted.
  if method == 'exit'
    notif->remove('params')
  endif
"""
if fix not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, needle + fix))
text = path.read_text()
needle = '  initparams.processId = getpid()\n'
fix = """  # Downstream: the editor is outside the Sandbox helper PID namespace.
  initparams.processId = get(g:, 'vimconfig_profile', '') == 'sandbox' ? v:null : getpid()
"""
if fix not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, fix))
path = root / 'autoload/lsp/util.vim'
text = path.read_text()
needle = '  return uri_decoded\n'
fix = """  # Downstream: reject excluded locations before buffer lookup/loading.
  if exists('*g:VimConfigLspPathAllow') && !g:VimConfigLspPathAllow(uri_decoded)
    throw 'vim-config: language server returned an excluded path'
  endif
  return uri_decoded
"""
if fix not in text:
    assert text.count(needle) == 1
    path.write_text(text.replace(needle, fix))
