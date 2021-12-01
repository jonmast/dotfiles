" Enable by adding this to vimrc:
" let test#custom_runners = {'Ruby': ['rails_decorators']}

" Override patterns to add decorator regex
let test#ruby#patterns = {
  \ 'test': [
    \ '\v^\s*def (test_\w+)',
    \ '\v^\s*test%(\(| )%("|'')(.*)%("|'')',
    \ '\v^\s*it%(\(| )%("|'')(.*)%("|'')',
  \],
  \ 'namespace': [
    \ '\v^\s*%(class|module) (\S+)',
    \ '\v^\s*describe%(\(| )%("|'')(.*)%("|'')',
    \ '\v^\s*describe%(\(| )(\S+)',
    \ '\v^\s*decorate%(\(| )([[:alnum:]:]+),',
  \],
\}

if !exists('g:test#ruby#rails_decorators#file_pattern')
  let g:test#ruby#rails_decorators#file_pattern = '\v(((^|/)test_.+)|_test)\.decorator$'
endif

function! test#ruby#rails_decorators#test_file(file) abort
  return a:file =~# g:test#ruby#rails_decorators#file_pattern
endfunction

function! test#ruby#rails_decorators#build_position(type, position) abort
  " Forward to minitest implementation
  return test#ruby#minitest#build_position(a:type, a:position)
endfunction


function! test#ruby#rails_decorators#build_args(args) abort
  for idx in range(0, len(a:args) - 1)
    if test#base#file_exists(a:args[idx])
      let path = s:gem_path(remove(a:args, idx)) | break
    endif
  endfor

  for option in ['--name', '--seed']
    let idx = index(a:args, option)
    if idx != -1
      let value = remove(a:args, idx + 1)
      let a:args[idx] = option.'='.shellescape(value, 1)
    endif
  endfor

  return ['test', path] + a:args
endfunction

function! s:gem_path(decorator_path) abort
  let ruby_file = substitute(a:decorator_path, 'decorator$', 'rb', '')

  for [gem, gem_root] in items(bundler#project().paths())
    let full_path = gem_root . '/' . ruby_file

    if filereadable(full_path)
      return full_path
    endif
  endfor

  throw "Unable to find decorated class at " . ruby_file
endfunction

function! test#ruby#rails_decorators#executable() abort
  return 'bin/rails'
endfunction
