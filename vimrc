set nocompatible       " be iMproved
filetype on            " required!
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
"show trailing whitespace
"set list
"set listchars=tab:▷⋅,trail:⋅,nbsp:⋅
set wrap               "dont wrap lines
set linebreak          "wrap lines at convenient points
set nu
set guitablabel=%t
set ts=2               " Tabs are 2 spaces
set bs=2               " Backspace over everything in insert mode
set shiftwidth=2       " Tabs under smart indent
set nocp               incsearch
set formatoptions=tcqr
"set cindent
set autoindent
set smarttab
set expandtab
"vertical/horizontal scroll off settings
set scrolloff=3
set sidescrolloff=7
set sidescroll=1
"load ftplugins and indent files
filetype plugin        on
filetype indent        on
syntax on
"hide buffers when not displayed
set hidden
set history=256        " Number of things to remember in history.
set timeoutlen=250     " Time to wait after ESC (default causes an annoying delay)
set completeopt=longest,menuone

set novisualbell       " No blinking .
set noerrorbells       " No noise.
" Move to the next buffer
nmap <leader>l :bnext<CR>

" Move to the previous buffer
nmap <leader>h :bprevious<CR>

" gvim specific
set mousehide  " Hide mouse after chars typed
if v:version >= 703
    "undo settings
    set undodir=~/.vim/undofiles
    set undofile

    "set colorcolumn=+1 "mark the ideal max text width
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

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0
endif

" For HTML
autocmd FileType html set omnifunc=htmlcomplete#CompleteTags

" For CSS
autocmd BufNewFile,BufRead *.scss set ft=scss.css

" For Ruby
"autocmd FileType ruby,eruby set omnifunc=rubycomplete#Complete
"autocmd FileType ruby,eruby let g:rubycomplete_buffer_loading = 1
"autocmd FileType ruby,eruby let g:rubycomplete_rails = 1
"autocmd FileType ruby,eruby let g:rubycomplete_classes_in_global = 1

inoremap <C-s> <esc>:w<cr>a
nmap <CR> o<Esc>
vmap <Enter> <Plug>(EasyAlign)
" quick access buffer stuff
map gn :bn<cr>
map gp :bp<cr>
map gd :bd<cr>

set rtp+=~/.vim/bundle/Vundle.vim/
call vundle#begin()

" let Vundle manage Vundle
" required!
Plugin 'gmarik/Vundle.vim'

" My bundles here:
"Plugin 'Lokaltog/powerline', {'rtp': 'powerline/bindings/vim/'}
Plugin 'scrooloose/syntastic'
Plugin 'tpope/vim-fugitive'
Plugin 'tpope/vim-vividchalk'
Plugin 'tpope/vim-obsession'
Plugin 'scrooloose/nerdcommenter'
Plugin 'tpope/vim-rails'
Plugin 'tpope/vim-endwise'
Plugin 'scrooloose/nerdtree'
Plugin 'Valloric/YouCompleteMe'
Plugin 'junegunn/vim-easy-align'
Plugin 'quanganhdo/grb256'
Plugin 'bling/vim-airline'
Plugin 'kien/ctrlp.vim'
Plugin 'ap/vim-css-color'
Plugin 'ntpeters/vim-better-whitespace'
call vundle#end()

set background=dark
colorscheme vividchalk
command! W w !sudo tee % > /dev/null
nmap <Leader>e :e <C-R>=expand("%:p:h") . "/" <CR>
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:syntastic_always_populate_loc_list = 1

