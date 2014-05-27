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
