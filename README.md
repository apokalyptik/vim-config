vim-config
==========

My personal vim configuration

```bash
cd $HOME
mkdir -p $HOME/.vim/colors
wget -O - https://raw.githubusercontent.com/apokalyptik/vim-config/master/.vimrc > $HOME/.vimrc
wget -O - https://raw.githubusercontent.com/fatih/molokai/master/colors/molokai.vim > $HOME/.vim/colors/molokai.vim
git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
```

Now you can open up vim. Run :PluginInstall, and quit vim to make all of these things take effect

At work our sandboxes are running debian wheezy.  And the vim version is too old for both neocomplete and YouCompleteMe.  I built vim 7.4 .deb files for the purpose of working around this limitation. To use rhese replacement vim files we need to do the following:

```bash
mkdir -p $HOME/.local

wget -O $HOME/.local/vim-nox_7.4.273-2_amd64.deb \
  https://github.com/apokalyptik/vim-config/raw/master/debian-wheezy-amd64/vim-nox_7.4.273-2_amd64.deb
dpkg -X $HOME/.local/vim-nox_7.4.273-2_amd64.deb $HOME/.local

wget -O $HOME/.local/vim-runtime_7.4.273-2_all.deb \
  https://github.com/apokalyptik/vim-config/raw/master/debian-wheezy-amd64/vim-runtime_7.4.273-2_all.deb
dpkg -X $HOME/.local/vim-runtime_7.4.273-2_all.deb $HOME/.local
```

Now you can just set this alias in your .bashrc or .bash_profile

```bash
alias vim="env VIMRUNTIME=$HOME/.local/usr/share/vim/vim74 $HOME/.local/usr/bin/vim.nox"
```
