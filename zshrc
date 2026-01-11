export ASDF_DATA_DIR="$HOME/.asdf"
export PATH=.git/safe/../../bin:$ASDF_DATA_DIR/shims:$HOME/.local/bin:$PATH:$HOME/.yarn/bin:$HOME/.cargo/bin

# export CARGO_TARGET_DIR=~/.cargo/build_cache
export ZSH_PLUGINS_ALIAS_TIPS_TEXT="💡 Alias tip: "
export ZSH_PLUGINS_ALIAS_TIPS_EXPAND=1
export NVIM_TUI_ENABLE_TRUE_COLOR=1
export HOMEBREW_CASK_OPTS="--no-quarantine"
export FZF_DEFAULT_COMMAND='rg --files'

# load custom completions
fpath=(~/.zsh ~/.asdf/completions $fpath)

if type brew &>/dev/null
then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi


# Load antigen
source ~/.dotfiles/antigen/antigen.zsh
DEFAULT_USER="jon"
COMPLETION_WAITING_DOTS="true"
antigen use oh-my-zsh
antigen bundle git
antigen bundle history-substring-search
antigen bundle vi-mode
antigen bundle zdharma-continuum/fast-syntax-highlighting
antigen bundle archlinux
antigen bundle rails
antigen bundle djui/alias-tips
antigen bundle docker
antigen bundle docker-compose
antigen bundle yarn
antigen apply

# ASDF requires compinit, but it should be run after OMZ init
# autoload -Uz compinit
# compinit
# [[ -a $HOME/.asdf/asdf.sh ]] && source $HOME/.asdf/asdf.sh

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
# New fzf install
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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
[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"
ghcs() {
	FUNCNAME="$funcstack[1]"
	TARGET="shell"
	local GH_DEBUG="$GH_DEBUG"
	local GH_HOST="$GH_HOST"

	read -r -d '' __USAGE <<-EOF
	Wrapper around \`gh copilot suggest\` to suggest a command based on a natural language description of the desired output effort.
	Supports executing suggested commands if applicable.

	USAGE
	  $FUNCNAME [flags] <prompt>

	FLAGS
	  -d, --debug           Enable debugging
	  -h, --help            Display help usage
	      --hostname        The GitHub host to use for authentication
	  -t, --target target   Target for suggestion; must be shell, gh, git
	                        default: "$TARGET"

	EXAMPLES

	- Guided experience
	  $ $FUNCNAME

	- Git use cases
	  $ $FUNCNAME -t git "Undo the most recent local commits"
	  $ $FUNCNAME -t git "Clean up local branches"
	  $ $FUNCNAME -t git "Setup LFS for images"

	- Working with the GitHub CLI in the terminal
	  $ $FUNCNAME -t gh "Create pull request"
	  $ $FUNCNAME -t gh "List pull requests waiting for my review"
	  $ $FUNCNAME -t gh "Summarize work I have done in issues and pull requests for promotion"

	- General use cases
	  $ $FUNCNAME "Kill processes holding onto deleted files"
	  $ $FUNCNAME "Test whether there are SSL/TLS issues with github.com"
	  $ $FUNCNAME "Convert SVG to PNG and resize"
	  $ $FUNCNAME "Convert MOV to animated PNG"
	EOF

	local OPT OPTARG OPTIND
	while getopts "dht:-:" OPT; do
		if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
			OPT="${OPTARG%%=*}"       # extract long option name
			OPTARG="${OPTARG#"$OPT"}" # extract long option argument (may be empty)
			OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
		fi

		case "$OPT" in
			debug | d)
				GH_DEBUG=api
				;;

			help | h)
				echo "$__USAGE"
				return 0
				;;

			hostname)
				GH_HOST="$OPTARG"
				;;

			target | t)
				TARGET="$OPTARG"
				;;
		esac
	done

	# shift so that $@, $1, etc. refer to the non-option arguments
	shift "$((OPTIND-1))"

	TMPFILE="$(mktemp -t gh-copilotXXXXXX)"
	trap 'rm -f "$TMPFILE"' EXIT
	if GH_DEBUG="$GH_DEBUG" GH_HOST="$GH_HOST" gh copilot suggest -t "$TARGET" "$@" --shell-out "$TMPFILE"; then
		if [ -s "$TMPFILE" ]; then
			FIXED_CMD="$(cat $TMPFILE)"
			print -s -- "$FIXED_CMD"
			echo
			eval -- "$FIXED_CMD"
		fi
	else
		return 1
	fi
}

ghce() {
	FUNCNAME="$funcstack[1]"
	local GH_DEBUG="$GH_DEBUG"
	local GH_HOST="$GH_HOST"

	read -r -d '' __USAGE <<-EOF
	Wrapper around \`gh copilot explain\` to explain a given input command in natural language.

	USAGE
	  $FUNCNAME [flags] <command>

	FLAGS
	  -d, --debug      Enable debugging
	  -h, --help       Display help usage
	      --hostname   The GitHub host to use for authentication

	EXAMPLES

	# View disk usage, sorted by size
	$ $FUNCNAME 'du -sh | sort -h'

	# View git repository history as text graphical representation
	$ $FUNCNAME 'git log --oneline --graph --decorate --all'

	# Remove binary objects larger than 50 megabytes from git history
	$ $FUNCNAME 'bfg --strip-blobs-bigger-than 50M'
	EOF

	local OPT OPTARG OPTIND
	while getopts "dh-:" OPT; do
		if [ "$OPT" = "-" ]; then     # long option: reformulate OPT and OPTARG
			OPT="${OPTARG%%=*}"       # extract long option name
			OPTARG="${OPTARG#"$OPT"}" # extract long option argument (may be empty)
			OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
		fi

		case "$OPT" in
			debug | d)
				GH_DEBUG=api
				;;

			help | h)
				echo "$__USAGE"
				return 0
				;;

			hostname)
				GH_HOST="$OPTARG"
				;;
		esac
	done

	# shift so that $@, $1, etc. refer to the non-option arguments
	shift "$((OPTIND-1))"

	GH_DEBUG="$GH_DEBUG" GH_HOST="$GH_HOST" gh copilot explain "$@"
}
