source ~/perl5/perlbrew/etc/bashrc
export PATH=.git/safe/../../bin:$HOME/.rbenv/bin:$PATH:$HOME/.yarn/bin:$HOME/.cargo/bin:$HOME/.local/bin:./bin
eval "$(rbenv init -)"
export PATH=.git/safe/../../bin:$PATH

export ZSH_PLUGINS_ALIAS_TIPS_TEXT="💡 Alias tip: "
export ZSH_PLUGINS_ALIAS_TIPS_EXPAND=1

# Load antigen
source ~/.dotfiles/antigen/antigen.zsh
DEFAULT_USER="jon"
COMPLETION_WAITING_DOTS="true"
antigen use oh-my-zsh
antigen bundle git
antigen bundle git-flow
# antigen bundle bundler
antigen bundle capistrano
antigen bundle history-substring-search
antigen bundle vi-mode
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle archlinux
antigen bundle rails
antigen bundle mix
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

# export TERM="xterm-256color"
alias tmux="env TERM=xterm-256color tmux" #hopefully fix strange vim+tmux issues

source /usr/share/fzf/key-bindings.zsh

# fbr - checkout git branch (including remote branches)
fbr() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" |
           fzf-tmux -d $(( 2 + $(wc -l <<< "$branches") )) +m) &&
  git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}

unalias g
function g {
  if [[ $# > 0 ]]; then
    git "$@"
  else
    echo "Last commit: $(time_since_last_commit) ago"
    git status --short --branch
  fi
}

compdef g=git

function time_since_last_commit() {
  ref=$(git symbolic-ref HEAD 2> /dev/null) || return
  git log -1 --pretty=format:"%ar" | sed 's/\([0-9]*\) \(.\).*/\1\2/'
}

source ${ZSH_CACHE_DIR}/fasd-init-cache

# Keybindings for history serarch
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# count potential duplicate migrations
# for file in $(cat files); do f=$(echo $file | sed s/[^_]*_//); find db/migrate -name "*$f" | wc -l | xargs echo $file; done
