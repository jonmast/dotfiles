# Path to your oh-my-zsh configuration.
source ~/.dotfiles/antigen/antigen.zsh
# [[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"
# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="blinks"
DEFAULT_USER="jon"
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how many often would you like to wait before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
DISABLE_LS_COLORS="false"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
antigen use oh-my-zsh
antigen bundle git
antigen bundle rvm
antigen bundle bundler
antigen bundle vi-mode
antigen bundle tmuxinator
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle archlinux
antigen theme blinks
antigen apply

setopt no_hist_verify
source $HOME/.bash_aliases
#set my custom ls colors
eval $( dircolors -b $HOME/.LS_COLORS )
# Customize to your needs...
export EDITOR=vim
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:$PATH
# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
export WORKON_HOME=$HOME/.virtualenvs
export PIP_VIRTUALENV_BASE=$WORKON_HOME
export PIP_RESPECT_VIRTUALENV=true
export _JAVA_OPTIONS='-Dawt.useSystemAAFontSettings=gasp'

#export LANG=en_US.utf8
export TERM="xterm-256color"
alias tmux="tmux -2" #hopefully fix strange vim+tmux issues
PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting
PATH=$PATH:$HOME/dev/android-studio/sdk/platform-tools:$HOME/dev/android-studio/sdk/tools:$HOME/dev/android-studio/bin # android studio and sdk
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
bindkey "^R" history-incremental-search-backward
