" Open and manage buffers.
" Version: 0.1.0
" Author : thinca <thinca+vim@gmail.com>
" License: Creative Commons Attribution 2.1 Japan License
"          <http://creativecommons.org/licenses/by/2.1/jp/deed.en>

let s:save_cpo = &cpo
set cpo&vim


unlet! g:openbuf#version  " To reload.
let g:openbuf#version = str2nr(printf('%2d%02d%03d', 0, 1, 0))
lockvar g:openbuf#version

" UI functions.  {{{1
let s:registered = {}

function! openbuf#new(...)  " {{{2
  let obj = deepcopy(s:Openbuf)
  let name = ''
  for a in a:000
    if type(a) == type('') && a != ''
      " {name}
      let name = a

    elseif type(a) == type({})
      " {config}
      let obj._config = s:extend(obj._config, a)

    endif
    unlet a
  endfor
  if name != ''
    call openbuf#register(name, obj)
  endif
  return obj
endfunction

function! openbuf#register(name, openbuf)  " {{{2
  if a:name == ''
    throw 'openbuf: name is empty.'
  endif
  if a:name == '_'
    throw 'openbuf: "_" is a reserved name.'
  endif
  if a:openbuf.is_registered() && a:openbuf.name() !=# a:name
    call a:openbuf.unregister()
  endif
  if has_key(s:registered, a:name)
    let s:registered[a:name]._config = a:openbuf._config
  else
    let s:registered[a:name] = a:openbuf
    let a:openbuf._name = a:name
  endif
endfunction

function! openbuf#get(name)  " {{{2
  return get(s:registered, a:name)
endfunction


" Config. {{{1
" default config. {{{2
unlet! g:openbuf#default_config
let g:openbuf#default_config = {
\   'reuse': 'tabpage',
\   'opener': 'split',
\   'silent': 0,
\   'nomanage': 0,
\ }
lockvar! g:openbuf#default_config

" config stack. {{{2
let s:config_stack = []

function! openbuf#execute_with(config, cmd)  " {{{3
  call insert(s:config_stack, a:config)
  try
    execute cmd
  finally
    call remove(s:config_stack, 0)
  endtry
endfunction

" Config object for internal.  {{{2
let s:Config = {}

function! s:Config.new(openbuf, configs)  " {{{3
  let conf = copy(self)
  let conf.openbuf = a:openbuf
  call conf.initialize(a:configs)
  return conf
endfunction

function! s:Config.initialize(configs)  " {{{3
  let configs = s:config_stack + a:configs
  let oc = self.openbuf._config
  if has_key(oc, 'force')
    call insert(configs, oc.force)
  endif

  if exists('g:openbuf#config') && self.openbuf.is_registered()
    let user_conf = ['_']
    let name = split(self.openbuf.name(), '/')
    for i in range(len(name))
      call insert(user_conf, join(name[: i], '/'))
    endfor

    let configs += map(filter(user_conf, 'has_key(g:openbuf#config, v:val)'),
    \                  'g:openbuf#config[v:val]')
  endif

  let configs += [oc, g:openbuf#default_config]

  call map(configs, 'type(v:val) == type("") ? {"bufname": v:val} : v:val')

  let config = {}
  for c in configs
    call s:extend(config, c)
  endfor

  let self.config = config
endfunction

function! s:Config.get(name, ...)  " {{{3
  if !has_key(self.config, a:name)
    if a:0
      return a:1
    else
      throw 'openbuf: no config: ' . a:name
    endif
  endif
  return s:value(self.config[a:name], self)
endfunction



" Openbuf object. {{{1
let s:Openbuf = {
\   '_config': {},
\   '_bufnrs': {},
\   '_bufnames': {},
\ }

function! s:Openbuf.name()  " {{{2
  return has_key(self, '_name') ? self._name : ''
endfunction

function! s:Openbuf.open(...)  " {{{2
  call self.gc()

  let config = s:Config.new(self, a:000)
  let buffer = config.get('bufname', self.name())
  let opener = config.get('opener')
  if opener[0] == '='
    let opener = eval(opener[1 :])
  endif
  let reuse = config.get('reuse')

  if has_key(self._bufnames, buffer)
    let buffer = self._bufnames[buffer]
  endif

  if reuse ==# 'always' || reuse ==# 'tabpage'
    let near = self.nearest(reuse ==# 'tabpage')
    if !empty(near)
      execute 'tabnext' near[0]
      execute near[1] 'wincmd w'
      let opener = 'edit'
    endif
  endif

  if config.get('silent')
    let opener = 'silent ' . opener
  endif

  let lastbuf = bufnr('$')

  if buffer is ''
    execute opener
    enew
  elseif type(buffer) == type('')
    execute opener '`=buffer`'
  else
    execute opener
    execute buffer 'buffer'
  endif

  if type(buffer) == type('') && !config.get('nomanage')
    call self.add(bufnr('%'), buffer)
  endif
  return lastbuf < bufnr('%')
endfunction

function! s:Openbuf.add(bufnr, ...)  " {{{2
  if bufexists(a:bufnr)
    let bufname = a:0 ? a:1 : bufname(a:bufnr)
    let self._bufnrs[a:bufnr] = bufname
    if bufname != ''
      let self._bufnames[bufname] = a:bufnr
    endif
  endif
endfunction

function! s:Openbuf.remove(bufnr)  " {{{2
  if has_key(self._bufnrs, a:bufnr)
    call remove(self._bufnrs, a:bufnr)
    call filter(self._bufnames, 'v:val != a:bufnr')
  endif
endfunction

function! s:Openbuf.is_managed(bufnr)  " {{{2
  return has_key(self._bufnrs, a:bufnr)
endfunction

function! s:Openbuf.list()  " {{{2
  return sort(keys(self._bufnrs))
endfunction

function! s:Openbuf.config(...)  " {{{2
  if a:0 && type(a:1) == type({})
    let self._config = a:1
  endif
  return self._config
endfunction

function! s:Openbuf.gc()  " {{{2
  call filter(self._bufnrs, 'bufexists(v:key - 0)')
  call filter(self._bufnames, 'bufexists(v:val)')
endfunction

function! s:Openbuf.nearest(...)  " {{{2
  call self.gc()
  let tabpageonly = a:0 && a:1

  if tabpageonly
    let tabpages = [tabpagenr()]
  else
    let s:base = tabpagenr()
    let tabpages = sort(range(1, tabpagenr('$')), 's:distance')
  endif

  for tabnr in tabpages
    let s:base = tabpagewinnr(tabnr)
    let buflist = tabpagebuflist(tabnr)
    for winnr in sort(range(1, len(buflist)), 's:distance')
      if self.is_managed(buflist[winnr - 1])
        return [tabnr, winnr, buflist[winnr - 1]]
      endif
    endfor
  endfor
  return []
endfunction

function! s:Openbuf.do(cmd)  " {{{2
  let cmd = a:cmd =~ '%s' ? a:cmd : a:cmd . ' %s'
  for bufnr in self.list()
    execute substitute(cmd, '%s', bufnr, '')
  endfor
endfunction

function! s:Openbuf.is_registered()  " {{{2
  return has_key(self, '_name')
endfunction

function! s:Openbuf.unregister()  " {{{2
  if has_key(s:registered, self.name())
    unlet s:registered[self.name()]
  endif
  unlet! self._name
  return self
endfunction



" Wrappers for openbuf object {{{1
function! s:get_or_create(name)  " {{{2
  let obj = openbuf#get(a:name)
  return obj is 0 ? openbuf#new(a:name) : obj
endfunction

let s:type_func = type(function('function'))
for s:func in keys(filter(copy(s:Openbuf),
\                         'v:key[0] != "_" && type(v:val) == s:type_func'))
  execute join([
  \ 'function! openbuf#' . s:func . '(name, ...)',
  \ '  let obj = s:get_or_create(a:name)',
  \ '  return call(obj.' . s:func . ', a:000, obj)',
  \ 'endfunction'], "\n")
endfor
unlet! s:type_func s:func



" Misc functions. {{{1
function! s:value(val, self)  " {{{2
  let val = a:val
  while type(val) == type(function('function'))
    let val = call(val, [], a:self)
  endwhile
  return val
endfunction

function! s:extend(a, b)  " {{{2
  let d = type({})
  for [k, v] in items(a:b)
    if !has_key(a:a, k)
      let a:a[k] = v
    elseif type(a:a[k]) == d && type(v) == d
      call s:extend(a:a[k], v)
    endif
  endfor
  return a:a
endfunction

" Comparison function to sort it based on distance from s:base.
function! s:distance(a, b)  " {{{2
  return abs(a:a - s:base) - abs(a:b - s:base)
endfunction



" END. {{{1
let &cpo = s:save_cpo
unlet s:save_cpo
