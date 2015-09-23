#! /bin/bash
#
# Autopilot configurator for local Git config, Git-aware Bash prompt and Bash completion.
# Helps bootstrap Git training sessions much faster, but can help anyone else, I guess…
#
# (c) 2015 Christophe Porteneuve <christophe@delicious-insights.com>

[ -z "$DEBUG" ] || set -x

CONFIG_GIST_RAW_URL='https://gist.githubusercontent.com/tdd/470582/raw/bdf1f13c13521f43d2422dfe7e60cf1e7d6dd562'
CYAN=36
GREEN=32
PROMPT_GIST_RAW_URL='https://gist.githubusercontent.com/tdd/594d37179ee9b36e1ba3/raw/4bec440234260f1f1e9e098b2731e0321435a6d9'
RED=31
[ 'MINGW32' = "$MSYSTEM" ] && ISWINDOWS=true || ISWINDOWS=false

if sed -r '' &> /dev/null <<< ''; then
  sed_extended='-r'
  sed_inplace="-i'' "
  $ISWINDOWS && sed_inplace='-i'
else
  sed_extended='-E'
  sed_inplace="-i ''"
fi

function announce()
{
  echo ''
  colorize $CYAN "$@"
  colorize $CYAN $(echo "$@" | sed 's/./=/g')
  echo ''
}

function colorize()
{
  local color="$1"
  shift
  if test -t 0; then
    echo -e "\033[1;${color}m""$@""\033[0m"
  else
    echo "$@"
  fi
}

function config()
{
  display_detected_os
  ensure_global_config
  ensure_prompt
  ensure_completion
  echo ''
  reverse 76 ''
  reverse 76 'DONE!  Run this if you want these settings immediately available:'
  reverse 76 ''
  reverse 76 "source $(get_proper_bash_config_file)"
  reverse 76 ''
  reverse 76 'Otherwise, just restart a fresh terminal to have them auto-loaded.'
  reverse 76 ''
  echo ''
}

function display_detected_os()
{
  local os linux_type
  case $(uname -s) in
    *Darwin*)         os='OSX';;
    *MINGW*|*CYGWIN*) os='Windows (Cygwin)';;
    *)
      [ -f "/etc/issue" ] && linux_type=" ($(cat /etc/issue | sed 's/ *\\\\.*$//'))"
      os="Linux${linux_type}"
      ;;
  esac
  announce "Detected OS: $os"
}

function ensure_completion()
{
  announce 'Completion verification'

  if $ISWINDOWS || complete -pr git &> /dev/null; then
    notice 'A completion is defined, leaving well enough alone.'
  else
    local file=$(get_proper_bash_config_file)
    local paths=$(get_proper_git_ps1_file)
    if [ -n "$paths" ]; then
      local earliest_file=$(echo "$paths" | head -n 1)
      notice "Loading Git completion definitions from ${earliest_file}…"
      echo -e "\n# Git completion definitions" >> "$file"
      echo "source '$earliest_file'" >> "$file"
    else
      ko 'Unable to find a Git completion source :-(\n'
      return
    fi
  fi

  ok '\n\\o/ Completion verification complete!\n'
}

function ensure_global_config()
{
  announce 'Global configuration'

  local path=$(get_global_config_path)
  local contents=$(curl -s "$CONFIG_GIST_RAW_URL")
  local username=$(get_config_entry user.name) email=$(get_config_entry user.email)

  try_backing_up "$path"
  notice "Resetting $path to our recommended settings…"
  echo "$contents" > "$path"

  notice "Restoring / setting your identity…"
  ensure_value user.name "$username" "Your full name"
  ensure_value user.email "$email" "Your e-mail address"

  if [ -f "$path.bak" ]; then
    notice "Merging your existing settings that we didn’t (re)define…"
    git config -f "$path.bak" --list | {
      IFS==
      while read name value; do
        merge_value "$name" "$value"
      done
    }
  fi

  ok '\n\\o/ Global configuration complete!\n'
}

function ensure_prompt()
{
  announce "Bash prompt customization"

  local file=$(get_proper_bash_config_file)
  local contents=$(curl -s "$PROMPT_GIST_RAW_URL" | grep -v '^#\|^$')

  notice 'Commenting out former Git/PS1 environment variables…'
  if [ -f "$file" ]; then
    try_backing_up "$file" copy
    sed $sed_inplace $sed_extended 's/^export (GIT_|PS1)/\n### Commented by Git Attitude Config Script\n# export \1/g' "$file"
  fi

  notice 'Adding new definitions…'
  echo '' >> "$file"
  echo "$contents" >> "$file"

  source "$file"

  if $ISWINDOWS || [ "function" = "$(type -t __git_ps1)" ]; then
    notice 'A Git prompt definition (__git_ps1) is already present: leaving it untouched.'
  else
    local paths=$(get_proper_git_ps1_file)
    if [ -n "$paths" ]; then
      local latest_file=$(echo "$paths" | tail -n 1)
      notice "Loading Git prompt definitions from ${latest_file}…"
      echo -e "\n# Git completion and prompt definitions" >> "$file"
      echo "$paths" | while read -r path; do
        echo "source '$path'" >> "$file"
      done
    else
      ko 'Unable to find a Git prompt/completion source :-(\n'
      return
    fi
  fi

  echo -e "\n\n# So people can use 'l' as well\nfunction l() { ls -lA \"$@\"; }" >> "$file"

  ok '\n\\o/ Prompt configuration complete!\n'
}

function ensure_value()
{
  local value="$2"
  while [ -z "$value" ]; do
    echo -n "    -> $3 must be defined: " >&2
    read -r value >&2
  done
  git config --global "$1" "$value"
}

function get_config_entry()
{
  git config --global --get "$1" 2> /dev/null
}

function get_global_config_path()
{
  local default="$HOME/.gitconfig"
  [ -f "$default" ] && echo "$default" && return

  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
  [ -f "$xdg" ] && echo "$xdg" || echo "$default"
}

function get_proper_bash_config_file()
{
  for option in .bash_profile .bashrc .profile; do
    [ -f "$HOME/$option" ] && echo "$HOME/$option" && return
  done
  if uname -s | grep -q Darwin; then
    echo "$HOME/.profile"
  else
    echo "$HOME/.bash_profile"
  fi
}

function get_proper_git_ps1_file()
{
  local paths

  # Homebrew (OSX)
  if which brew &> /dev/null; then
    path=$(brew --prefix)/etc/bash_completion.d
    if [ -f "$path/git-prompt.sh" ]; then
      echo "$path/git-completion.bash"$'\n'"$path/git-prompt.sh"
      return
    fi
  fi

  # Local Git contribs
  path=/usr/local/git/contrib/completion
  if [ -f "$path/git-prompt.sh" ]; then
    echo "$path/git-completion.bash"$'\n'"$path/git-prompt.sh"
    return
  fi

  # Bash defaults
  path=/etc/bash_completion.d/git
  [ -f "$path" ] && echo "$path"
}

function ko()
{
  colorize $RED "$@"
}

function notice()
{
  echo '  - '"$@"
}

function ok()
{
  colorize $GREEN "$@"
}

function merge_value()
{
  local existing_value=$(git config --global --get "$1" 2> /dev/null)
  [ -n "$existing_value" ] && return
  echo -n '  ' && notice "$1 = $2"
  git config --global "$1" "$2"
}

function reverse()
{
  local width=$1 msg=" $2 " stayLeft=$3
  if [ -z "$stayLeft" ]; then
    local padding=$(((${width} - ${#msg}) / 2))
    msg=$(printf '%*s%s' $padding ' ' "$msg")
  fi
  local rightPadding=$((${width} - ${#msg}))
  msg=$(printf '%s%*s' "$msg" $rightPadding ' ')
  echo -e "  \033[47;30m${msg}\033[0m"
}

function try_backing_up()
{
  local path="$1" copy="$2" cmd=mv
  [ "$copy" ] && cmd=cp
  [ -f "$path" ] || return

  if [ -f "$path.bak" ]; then
    notice "A $path.bak file already existed: leaving it untouched."
  else
    $cmd "$path" "$path.bak" && notice "Your $path was backed up as $path.bak"
  fi
}

config
