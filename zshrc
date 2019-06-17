export PATH=$HOME/.local/bin:$PATH:$HOME/.yarn/bin:$HOME/.cargo/bin

export ZSH_PLUGINS_ALIAS_TIPS_TEXT="💡 Alias tip: "
export ZSH_PLUGINS_ALIAS_TIPS_EXPAND=1

autoload -Uz compinit && compinit
[[ -a $HOME/.asdf/asdf.sh ]] && source $HOME/.asdf/asdf.sh
[[ -a $HOME/.asdf/completions/asdf.bash ]] && source $HOME/.asdf/completions/asdf.bash

export PATH=.git/safe/../../bin:$PATH

compdef g=git
compdef mycli=mysql

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

# Like fbr, but only for local feature branches
ffbr() {
  local branch
  branch=$(git flow feature | fzf-tmux +m) &&
    git flow feature checkout $(echo $branch | sed "s/.* //")
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

fasd_cache="$ZSH_CACHE_DIR/.fasd-init-cache"
if type fasd &> /dev/null; then
  [[ -a $fasd_cache ]] || fasd --init posix-alias \
    zsh-hook zsh-ccomp zsh-ccomp-install zsh-wcomp zsh-wcomp-install \
    >| "$fasd_cache"

  source $fasd_cache
fi
unset fasd_cache

# Keybindings for history serarch
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# count potential duplicate migrations
# for file in $(cat files); do f=$(echo $file | sed s/[^_]*_//); find db/migrate -name "*$f" | wc -l | xargs echo $file; done
