# load rvm
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
export ZSH_PLUGINS_ALIAS_TIPS_TEXT="💡 Alias tip: "
export ZSH_PLUGINS_ALIAS_TIPS_EXPAND=1

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
antigen bundle mix-fast
antigen bundle autojump
antigen bundle djui/alias-tips
antigen theme blinks
antigen apply

setopt no_hist_verify
HISTSIZE=1000000
SAVEHIST=1000000

# Pass special characters through if no files match
# This allows using parameters like HEAD^ without quoting
unsetopt nomatch
stty -ixon
source $HOME/.aliases
#set my custom ls colors
eval $( dircolors -b $HOME/.LS_COLORS )
# Customize to your needs...
export EDITOR=nvim
export PATH=.git/safe/../../bin:$PATH:$HOME/.rvm/bin:$HOME/dev/Android/Sdk/platform-tools:$HOME/.local/bin:./bin

# export TERM="xterm-256color"
alias tmux="tmux -2" #hopefully fix strange vim+tmux issues

source /usr/share/fzf/key-bindings.zsh

# fbr - checkout git branch (including remote branches)
fbr() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" |
           fzf-tmux -d $(( 2 + $(wc -l <<< "$branches") )) +m) &&
  git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}

ir() {
  local project_root
  project_root=$(git rev-parse --show-toplevel || pwd)
  invoker list |
    grep "$project_root " |
    awk -F '|' '{ print $5 }' |
    xargs invoker reload
}

# Keybindings for history serarch
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
