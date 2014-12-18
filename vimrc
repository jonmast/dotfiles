set nocompatible       " be iMproved
set ai                 " set auto-indenting on for programming
set hlsearch           " highlight searches
set incsearch          " do incremental searching
set showmatch          " jump to matches when entering regexp
set mouse=a
set laststatus=2
set noshowmode
set showcmd            "show command as you type
set wildmode=longest,list,full
set wildmenu
set wildignorecase "case insensitive filename completion
set wrap               "dont wrap lines
set linebreak          "wrap lines at convenient points
set nu
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
  " let g:ctrlp_use_caching = 0
endif

" For HTML
autocmd FileType html set omnifunc=htmlcomplete#CompleteTags

" For CSS
autocmd BufNewFile,BufRead *.scss set ft=scss.css


set rtp+=~/.vim/bundle/Vundle.vim/
call vundle#begin()

" let Vundle manage Vundle
Plugin 'gmarik/Vundle.vim'

" My bundles here:
Plugin 'scrooloose/syntastic'
Plugin 'tpope/vim-obsession'
Plugin 'tpope/vim-rails'
Plugin 'tpope/vim-endwise'
Plugin 'tpope/vim-eunuch'
Plugin 'tpope/vim-abolish'
" Plugin 'scrooloose/nerdtree'
Plugin 'Valloric/YouCompleteMe'
Plugin 'junegunn/vim-easy-align'
Plugin 'bling/vim-airline'
Plugin 'kien/ctrlp.vim'
Plugin 'ap/vim-css-color'
Plugin 'ntpeters/vim-better-whitespace'
Plugin 'tomtom/tcomment_vim'
Plugin 'jwhitley/vim-colors-solarized'
Plugin 'airblade/vim-gitgutter'
Plugin 'kchmck/vim-coffee-script'
Plugin 'FelikZ/ctrlp-py-matcher'
Plugin 'christoomey/vim-tmux-navigator'
Plugin 'sjl/gundo.vim'
Plugin 'tpope/vim-dispatch'
Plugin 'thoughtbot/vim-rspec'
call vundle#end()

nnoremap <F5> :GundoToggle<CR>
inoremap <C-s> <esc>:w<cr>a
vmap <Enter> <Plug>(EasyAlign)
" quick access buffer stuff
map gn :bn<cr>
map gp :bp<cr>
map gd :bd<cr>
map gs :CtrlPBuffer<cr>


nmap <leader>y :CtrlPBuffer<cr>
nmap <leader>f :CtrlPMRUFiles<cr>
nmap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>

" RSpec.vim mappings
map <Leader>t :call RunCurrentSpecFile()<CR>
map <Leader>s :call RunNearestSpec()<CR>
map <Leader>l :call RunLastSpec()<CR>
map <Leader>a :call RunAllSpecs()<CR>

set background=dark
colorscheme solarized
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:syntastic_always_populate_loc_list = 1
let g:EclimCompletionMethod = 'omnifunc' " YCM + Eclim
let g:ctrlp_match_func = { 'match': 'pymatcher#PyMatch' }

syntax on
filetype on
filetype plugin        on
filetype indent        on
