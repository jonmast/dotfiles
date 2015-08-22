# load rvm
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
# Load antigen
source ~/.dotfiles/antigen/antigen.zsh
DEFAULT_USER="jon"
COMPLETION_WAITING_DOTS="true"
antigen use oh-my-zsh
antigen bundle git
antigen bundle rvm
antigen bundle bundler
antigen bundle capistrano
antigen bundle history-substring-search
antigen bundle vi-mode
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle archlinux
antigen bundle rails
antigen bundle autojump
antigen theme blinks
antigen apply

setopt no_hist_verify
stty -ixon
source $HOME/.aliases
#set my custom ls colors
eval $( dircolors -b $HOME/.LS_COLORS )
# Customize to your needs...
export EDITOR=vim
export PATH=$PATH:$HOME/.rvm/bin:$HOME/dev/Android/Sdk/platform-tools:./bin

export TERM="xterm-256color"
alias tmux="tmux -2" #hopefully fix strange vim+tmux issues
bindkey "^R" history-incremental-search-backward
