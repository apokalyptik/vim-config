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
  vim +PluginClean +PluginInstall +qall
  $HOME/.vim/bundles/
)
```

Setting up VIM on Debian Wheezy
===============================
Wheezy has an old version of vim that supports niether neocomplete nor youcompleteme. I built vim 7.4 .deb files for the purpose of working around this limitation. To use these replacement vim versions we need to do the following (as root):

```bash
(
# just to be on the safe side
  apt-get update
 
# VIM
  # install the new vim packages
  # from -- https://github.com/apokalyptik/vim-config/tree/master/debian-wheezy-amd64
  dpkg -i \
    vim-common_7.4.273-2_amd64.deb \
    vim-runtime_7.4.273-2_all.deb \
    vim-tiny_7.4.273-2_amd64.deb \
    vim_7.4.273-2_amd64.deb \
    vim-nox_7.4.273-2_amd64.deb
  # have apt resolve the dependencies, please.
  apt-get -fqqy install
 
# Go - all 3 are required for go (supports mercurial in "go get" and many "semi-core" programs hosted with it)
  apt-get install git subversion mercurial
 
# Allow building of YouCompleteMe (vim autocompleter)
  apt-get install make cmake python-dev libboost-python-dev libboost-system-dev libboost-filesystem-dev libboost-regex-dev
)
```
