alias jon='ssh jon@sandbox'
alias sudedit='sudoedit'
alias syncit='rsync -vaz --rsh="ssh -l jon" --exclude ".*" ~/dev/clreader/ sandbox:~/clreader'
alias update='sudo apt-get update'
alias install='sudo apt-get install'
alias uninstall='sudo apt-get remove'
alias remove="sudo apt-get remove"
alias search="apt-cache search"

# Git shortcuts
alias g='git'
alias ga='git add'
alias gps='git push'
alias gpl='git pull'
alias gl='git log'
alias gg='gl --decorate --oneline --graph --date-order --all'
alias gs='git status'
alias gst='gs'
alias gd='git diff'
alias gdc='gd --cached'
alias gm='git commit -m'
alias gma='git commit -am'
alias gb='git branch'
alias gba='git branch -a'
alias gc='git checkout'
alias gco='gc'
alias gra='git remote add'
alias grr='git remote rm'
alias gcl='git clone'
alias py='python'
alias clipcss='xclip -selection clipboard legacycss.tpl'
alias sassclip='sass -t compressed styles.scss legacycss.tpl && clipcss'
alias traceroute=tracepath
alias mm=middleman

alias aes=~/Downloads/google_appengine/dev_appserver.py
alias gae=/home/mast/Downloads/google_appengine/appcfg.py
alias vi=vim
alias ya=yaourt
