# Wat?
It's [servers.dat](http://code.svn.wordpress.org/servermattic/etc/servers.dat) syntax highlighting for VIM.  This will mean almost nothing to almost everybody... because almost nobody uses [Servermattic](http://code.svn.wordpress.org/servermattic/) but us...

## What's it, like, do?

This, mainly

![example](example.png)

# Installation

## Plain old regular standard VIM

Put these files in these places

1. [ftdetect/serversdat.vim](ftdetect/serversdat.vim) -> `~/.vim/ftdetect/serversdat.vim `
2. [syntax/serversdat.vim](syntax/serversdat.vim) -> `~/.vim/syntax/serversdat.vim`
3. [ftplugin/serversdat.vim](ftplugin/serversdat.vim) -> `~/.vim/ftplugin/serversdat.vim`

## Vim, using the [vim-plug](https://github.com/junegunn/vim-plug) plugin manager

Add `Plug 'apokalyptik/vim-servers-dot-dat'` to your ~/.vimrc and run `:PlugInstall`

## VIM, using the [Vundle](https://github.com/VundleVim/Vundle.vim) plugin manager

Add `Plugin 'apokalyptik/vim-servers-dot-dat'` to your ~/.vimrc and run `:PluginInstall`

## Others...

If you're smart enough to be using other VIM plugin managers, and know what this does, and need this, then i have faith that you're smart enough to adapt the examples above to whatever it is you're using :D
