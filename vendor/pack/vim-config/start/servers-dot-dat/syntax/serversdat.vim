if exists("b:current_syntax")
  finish
endif

syntax match sddFieldDelim "\v:"
syntax match sddRoleDelim  "\v,"
syntax match sddRoleBase   "\v[^,]+-base"
syntax match sddRoleDc     "\vdc-[^,]+"
syntax match sddHostDomain "\v\.?[^.]+\.[^.:]+:" contains=sddFieldDelim
syntax match sddEXTRA      /.\{-}\(:\|$\)/ nextgroup=sddSID      contains=sddFieldDelim
syntax match sddPRICE      /.\{-}\(:\|$\)/ nextgroup=sddEXTRA    contains=sddFieldDelim
syntax match sddROLES      /.\{-}\(:\|$\)/ nextgroup=sddPRICE    contains=sddFieldDelim,sddRoleBase,sddRoleDc,sddRoleDelim
syntax match sddLAN        /.\{-}\(:\|$\)/ nextgroup=sddROLES    contains=sddFieldDelim
syntax match sddHOSTNAME   /.\{-}\(:\|$\)/ nextgroup=sddLAN      contains=sddFieldDelim,sddHostDomain
syntax match sddWAN        /.\{-}\(:\|$\)/ nextgroup=sddHOSTNAME contains=sddFieldDelim
syntax match sddDC         /.\{-}\(:\|$\)/ nextgroup=sddWAN      contains=sddFieldDelim
syntax match sddSID        /.\{-}\(:\|$\)/ nextgroup=sddDC       contains=sddFieldDelim

syntax match sddComment "\v#.*$"

highlight def link sddComment Comment

highlight sddSID        ctermfg='darkmagenta'   guifg='darkmagenta'
highlight sddDC         ctermfg='darkblue'      guifg='darkblue'
highlight sddWAN        ctermfg='darkcyan'      guifg='darkcyan'
highlight sddHOSTNAME   ctermfg='lightgreen'    guifg='lightgreen'
highlight sddHostDomain ctermfg='darkyellow'    guifg='darkyellow'
highlight sddLAN        ctermfg='darkred'       guifg='darkred'
highlight sddROLES      ctermfg='lightblue'     guifg='lightblue'
highlight sddRoleBase   ctermfg='lightcyan'     guifg='lightcyan'
highlight sddRoleDC     ctermfg='lightcyan'     guifg='lightcyan'
highlight sddPRICE      ctermfg='darkgreen'     guifg='darkgreen'
highlight sddEXTRA      ctermfg='lightyellow'   guifg='lightyellow'

highlight sddFieldDelim ctermfg='NONE'          guifg='NONE'
highlight sddRoleDelim  ctermfg='NONE'          guifg='NONE'
