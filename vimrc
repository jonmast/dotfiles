set nocompatible       " be iMproved
set ai                 " set auto-indenting on for programming
set hlsearch           " highlight searches
set incsearch          " do incremental searching
set showmatch          " jump to matches when entering regexp
set ignorecase         " Case insensitive search
set smartcase          " Case sensitive if search contains capitals
set mouse=a
set laststatus=2
set noshowmode
set showcmd            "show command as you type
set wildmode=longest,list,full
set wildmenu
set wildignorecase "case insensitive filename completion
set wrap               "dont wrap lines
set linebreak          "wrap lines at convenient points
set number
set relativenumber
set guitablabel=%t
set ts=2               " Tabs are 2 spaces
set bs=2               " Backspace over everything in insert mode
set shiftwidth=2       " Tabs under smart indent
set nocp               incsearch
set formatoptions=tcqr
set autoindent
set smarttab
set expandtab
"vertical/horizontal scroll off settings
set scrolloff=3
set sidescrolloff=7
set sidescroll=1

"hide buffers when not displayed
set hidden
set history=256        " Number of things to remember in history.
set ttimeoutlen=100     " Time to wait after ESC (default causes an annoying delay)
set completeopt=longest,menuone

set splitbelow
set splitright

set novisualbell       " No blinking .
set noerrorbells       " No noise.

" gvim specific
set mousehide  " Hide mouse after chars typed
if v:version >= 703
    "undo settings
    set undodir=~/.vim/undofiles
    set undofile

endif
if has("gui_running")
  " GUI is running or is about to start.
  " Maximize gvim window.
  set lines=999 columns=999
endif

" The Silver Searcher
if executable('ag')
  " Use ag over grep
  set grepprg=ag\ --nogroup\ --nocolor

  " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
  let g:ctrlp_user_command = 'ag %s -l --nocolor -g ""'
  let g:ctrlp_lazy_update  = 350

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0
endif

if filereadable(expand('~/.vim_bundles'))
  source ~/.vim_bundles
endif

augroup vimrcEx
  autocmd!

  " For HTML
  autocmd FileType html set omnifunc=htmlcomplete#CompleteTags

  autocmd VimResized * :wincmd =
  " When editing a file, always jump to the last known cursor position.
  " Don't do it for commit messages, when the position is invalid, or when
  " inside an event handler (happens when dropping a file on gvim).
  autocmd BufReadPost *
    \ if &ft != 'gitcommit' && line("'\"") > 0 && line("'\"") <= line("$") |
    \   exe "normal g`\"" |
    \ endif
  autocmd BufRead,BufNewFile *.md set filetype=markdown
  autocmd FileType markdown setlocal spell
  autocmd BufRead,BufNewFile *.md setlocal textwidth=80
  autocmd FileType gitcommit setlocal spell
  " Allow stylesheets to autocomplete hyphenated words
  autocmd FileType css,scss,sass setlocal iskeyword+=-
  " Question marks are valid in ruby metods
  autocmd FileType ruby,eruby setlocal iskeyword+=?
augroup END

runtime macros/matchit.vim
nnoremap <F5> :GundoToggle<CR>
noremap <C-s> <esc>:w<cr>
vmap <Enter> <Plug>(EasyAlign)
" quick access buffer stuff
map gn :bn<cr>
map gp :bp<cr>
map gd :Bdelete<cr>
map gs :CtrlPBuffer<cr>
imap jk <Esc>

let mapleader = ' '
nmap <leader>y :CtrlPBuffer<cr>
nmap <leader>f :CtrlPMRUFiles<cr>
nmap <leader>rm :CtrlPModels<cr>
nmap <leader>rc :CtrlPControllers<cr>
nmap <leader>rv :CtrlPViews<cr>
nmap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>
nmap <Leader>h :nohl<CR>
nmap <Leader>v :tabe ~/.vimrc<CR>
nmap <Leader>w :w<CR>

" System clipboard mappings
vmap <Leader>y "+y
nmap <Leader>p "+p
nmap <Leader>P "+P

" RSpec.vim mappings
map <Leader>t :call RunCurrentSpecFile()<CR>
map <Leader>s :call RunNearestSpec()<CR>
map <Leader>l :call RunLastSpec()<CR>
map <Leader>a :call RunAllSpecs()<CR>

let g:rspec_command = "Dispatch bin/rspec {spec}"

" map semicolon to colon
nnoremap ; :

" bind K to grep word under cursor
nnoremap K :grep! "\b<C-R><C-W>\b"<CR>:cw<CR>

set background=dark
colorscheme solarized
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_ruby_checkers=['mri', 'rubocop']
let g:ctrlp_match_func = { 'match': 'pymatcher#PyMatch' }

let g:ycm_key_list_select_completion=['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion=['<C-p>', '<Up>']
let g:rubycomplete_rails = 1

let g:UltiSnipsExpandTrigger="<Tab>"
let g:UltiSnipsJumpForwardTrigger="<Tab>"
let g:UltiSnipsJumpBackwardTrigger="<S-Tab>"

syntax on
filetype on
filetype plugin        on
filetype indent        on
