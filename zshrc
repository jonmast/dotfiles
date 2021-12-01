export PATH=.git/safe/../../bin:$HOME/.local/bin:$PATH:$HOME/.yarn/bin:$HOME/.cargo/bin

export CARGO_TARGET_DIR=~/.cargo/build_cache
export ZSH_PLUGINS_ALIAS_TIPS_TEXT="💡 Alias tip: "
export ZSH_PLUGINS_ALIAS_TIPS_EXPAND=1
export NVIM_TUI_ENABLE_TRUE_COLOR=1
export HOMEBREW_CASK_OPTS="--no-quarantine"
export FZF_DEFAULT_COMMAND='rg --files'

# load custom completions
fpath=(~/.zsh $fpath)

# Load antigen
source ~/.dotfiles/antigen/antigen.zsh
DEFAULT_USER="jon"
COMPLETION_WAITING_DOTS="true"
antigen use oh-my-zsh
antigen bundle git
antigen bundle history-substring-search
antigen bundle vi-mode
antigen bundle zdharma/fast-syntax-highlighting
antigen bundle archlinux
antigen bundle rails
antigen bundle djui/alias-tips
antigen bundle docker
antigen bundle docker-compose
antigen apply

# ASDF requires compinit, but it should be run after OMZ init
autoload -Uz compinit
compinit
[[ -a $HOME/.asdf/asdf.sh ]] && source $HOME/.asdf/asdf.sh
[[ -a $HOME/.asdf/completions/asdf.bash ]] && source $HOME/.asdf/completions/asdf.bash

compdef g=git
compdef mycli=mysql
setopt no_hist_verify
HISTSIZE=1000000
SAVEHIST=1000000

# Pass special characters through if no files match
# This allows using parameters like HEAD^ without quoting
unsetopt nomatch
stty -ixon
setopt correct
source $HOME/.aliases

#set my custom ls colors
if [[ -a ~/.LS_COLORS ]]; then
  if type dircolors &> /dev/null; then
    eval $( dircolors -b $HOME/.LS_COLORS )
  else
    # Apple hates GNU, so they call it gdircolors
    if type gdircolors &> /dev/null; then
      eval $( gdircolors -b $HOME/.LS_COLORS )
    fi
  fi
fi

export EDITOR=nvim

if type delta &> /dev/null; then
  export GIT_PAGER=delta
fi

# export TERM="xterm-256color"
alias tmux="env TERM=xterm-256color tmux" #hopefully fix strange vim+tmux issues

# Linux path
[[ -a /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
# OSX
[[ -a  "/usr/local/opt/fzf/shell/key-bindings.zsh" ]] && source "/usr/local/opt/fzf/shell/key-bindings.zsh"

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

function time_since_last_commit() {
  ref=$(git symbolic-ref HEAD 2> /dev/null) || return
  git log -1 --pretty=format:"%ar" | sed 's/\([0-9]*\) \(.\).*/\1\2/'
}

if type zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# Keybindings for history search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

if type starship &> /dev/null; then
  eval "$(starship init zsh)"
fi
