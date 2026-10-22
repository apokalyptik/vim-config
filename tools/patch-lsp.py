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
path = root / 'autoload/lsp/lspserver.vim'
text = path.read_text()
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
