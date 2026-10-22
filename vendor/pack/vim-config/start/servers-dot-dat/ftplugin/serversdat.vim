setlocal nowrap
setlocal nospell

function! ServersDatCurrentHostname()
	let l:l = split( getline( '.' ), ':' )
	if len( l:l ) < 4
		return 'Unknown Hostname'
	endif
	return l:l[3]
endfunction

function! ServersdatCurrentColumnName()
	if !exists("*synstack")
		return ''
	endif

	let l:s = synID(line('.'), col('.'), 1)
	let l:n = synIDattr(l:s, 'name')

	if l:n == 'sddDelim'
		return ''
	elseif l:n == 'sddRoleDelim'
		return 'Roles'
	elseif l:n == 'sddSID'
		return 'Server ID'
	elseif l:n == 'sddDC'
		return 'Datacenter'
	elseif l:n == 'sddWAN'
		return 'WAN IP Address'
	elseif l:n == 'sddHOSTNAME'
		return 'Server Hostname'
	elseif l:n == 'sddHostDomain'
		return 'Server Hostname'
	elseif l:n == 'sddLAN'
		return 'LAN IP Address'
	elseif l:n == 'sddROLES'
		return 'Roles'
	elseif l:n == 'sddRoleDC'
		return 'Roles'
	elseif l:n == 'sddRoleBase'
		return 'Roles'
	elseif l:n == 'sddPRICE'
		return 'Server Cost'
	elseif l:n == 'sddEXTRA'
		return 'Extra'
	endif
	return ''
endfunction

function! ServersdatCurrentColumnSubName()
	if !exists("*synstack")
		return ''
	endif

	let l:s = synID(line('.'), col('.'), 1)
	let l:n = synIDattr(l:s, 'name')

	if l:n == 'sddHostDomain'
		return 'Domain Name'
	elseif l:n == 'sddRoleDC'
		return 'Datacenter Role'
	elseif l:n == 'sddRoleBase'
		return 'Base Role'
	elseif l:n == 'sddROLES'
		return 'Role'
	endif
	return ""
endfunction

function! ServersdatAirlineStatusFunc(...)
	if &filetype == 'serversdat'
		let w:airline_section_a = '%{ServersDatCurrentHostname()}'
		let w:airline_section_b = '%{ServersdatCurrentColumnName()}'
		let w:airline_section_c = '%{ServersdatCurrentColumnSubName()}'
	endif
endfunction

function! ServersdatManualStatusline()
	if &filetype == 'serversdat'
		highlight sddshn   ctermbg=Black ctermfg=LightGreen
		highlight sddscn   ctermbg=Black ctermfg=LightBlue
		highlight sddssn   ctermbg=Black ctermfg=LightCyan
		highlight sddsnone ctermbg=Black ctermfg=White
		set laststatus=2
		set statusline=
		set statusline+=%#sddshn#
		set statusline+=%{ServersDatCurrentHostname()}
		set statusline+=%#sddsnone#
		set statusline+=\ >\ 
		set statusline+=%#sddscn#
		set statusline+=%{ServersdatCurrentColumnName()}
		set statusline+=%#sddsnone#
		set statusline+=\ >\ 
		set statusline+=%#sddssn#
		set statusline+=%{ServersdatCurrentColumnSubName()}
		set statusline+=%#sddsnone#
	endif
endfunction

if exists( 'g:loaded_airline' )
	call airline#add_statusline_func('ServersdatAirlineStatusFunc')
else
	call ServersdatManualStatusline()
endif
