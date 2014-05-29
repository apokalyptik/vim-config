vim-config
==========

Installing My personal vim configuration
========================================

```bash
(
  mkdir -p $HOME/.vim/colors
  wget --quiet -O $HOME/.vimrc \
    https://raw.githubusercontent.com/apokalyptik/vim-config/master/.vimrc > $HOME/.vimrc
  wget --quiet -O $HOME/.vim/colors/molokai.vim \
    https://raw.githubusercontent.com/fatih/molokai/master/colors/molokai.vim
  git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
  env VIMRUNTIME=$HOME/.local/usr/share/vim/vim74 \
    LD_LIBRARY_PATH=$HOME/.local/usr/lib:$HOME/.local/usr/lib/x86_64-linux-gnu \
    $HOME/.local/usr/bin/vim.nox +PluginClean +PluginInstall +qall
)
```

Setting up VIM on Debian Wheezy
===============================
At work our sandboxes are running debian wheezy.  And the vim version is too old for both neocomplete and YouCompleteMe.  I built vim 7.4 .deb files for the purpose of working around this limitation. To use rhese replacement vim files we need to do the following:

```bash
(
  mkdir -p $HOME/.local

  wget --quiet -O $HOME/.local/liblua5.1-0_5.1.5-4_amd64.deb \
    http://ftp.us.debian.org/debian/pool/main/l/lua5.1/liblua5.1-0_5.1.5-4_amd64.deb
  wget --quiet -O $HOME/.local/tcl8.5_8.5.11-2_amd64.deb \
    http://ftp.us.debian.org/debian/pool/main/t/tcl8.5/tcl8.5_8.5.11-2_amd64.deb
  wget --quiet -O $HOME/.local/vim-nox_7.4.273-2_amd64.deb \
    https://github.com/apokalyptik/vim-config/raw/master/debian-wheezy-amd64/vim-nox_7.4.273-2_amd64.deb
  wget --quiet -O $HOME/.local/vim-runtime_7.4.273-2_all.deb \
    https://github.com/apokalyptik/vim-config/raw/master/debian-wheezy-amd64/vim-runtime_7.4.273-2_all.deb
  wget --quiet -O $HOME/.local/exuberant-ctags_5.9~svn20110310-4_amd64.deb \
    http://ftp.us.debian.org/debian/pool/main/e/exuberant-ctags/exuberant-ctags_5.9~svn20110310-4_amd64.deb
  
  for i in $HOME/.local/*.deb; do dpkg -X $i $HOME/.local; done
)
```

Now you can just set this alias in your .bashrc or .bash_profile

```bash
alias vim="env VIMRUNTIME=$HOME/.local/usr/share/vim/vim74 env LD_LIBRARY_PATH=$HOME/.local/usr/lib:$HOME/.local/usr/lib/x86_64-linux-gnu $HOME/.local/usr/bin/vim.nox"
```
