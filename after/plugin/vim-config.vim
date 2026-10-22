" Vim may source an unguarded package plugin again after the vimrc phase.
" Restore bounded data hooks before the initial file is read.
call vimconfig#data#setup()
