#! /bin/bash
#
# Autopilot configurator for local Git config, Git-aware Bash prompt and Bash completion.
# Helps bootstrap Git training sessions much faster, but can help anyone else, I guess…
#
# (c) 2015 Christophe Porteneuve <christophe@delicious-insights.com>

CONFIG_GIST_RAW_URL='https://gist.githubusercontent.com/tdd/473838/raw/c4647fc5b2f35e9b54ccbc02b6b401dd8a2eae1d'
CYAN=36
GREEN=32
PROMPT_GIST_RAW_URL='https://gist.githubusercontent.com/tdd/594d37179ee9b36e1ba3/raw/4bec440234260f1f1e9e098b2731e0321435a6d9'
RED=31

if sed -r '' &> /dev/null <<< ''; then
  sed_extended='-r'
  sed_inplace="-i'' "
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
  if tty -s <&1; then
    echo -e "\033[1;${color}m""$@""\033[0m"
  else
    echo "$@"
  fi
}

function config()
{
  ensure_local_config
  ensure_prompt
  ensure_completion
}

function ensure_completion()
{
  announce 'Vérification de la complétion'

  if complete -pr git &> /dev/null; then
    notice 'Une complétion est en place, tout roule.'
  else
    local file=$(get_proper_bash_config_file)
    local paths=$(get_proper_git_ps1_file)
    if [ -n "$paths" ]; then
      local earliest_file=$(echo "$paths" | head -n 1)
      notice "Chargement des définitions de complétion pour Git depuis ${earliest_file}…"
      echo -e "\n# Git completion definitions" >> "$file"
      echo "source '$earliest_file'" >> "$file"
    else
      ko 'Impossible de trouver une source de complétion Git :-(\n'
      return
    fi
  fi

  ok '\n\\o/ Vérification de la complétion terminée !\n'
}

function ensure_local_config()
{
  announce 'Configuration globale'

  local path=$(get_local_config_path)
  local contents=$(curl -s "$CONFIG_GIST_RAW_URL")
  local username=$(get_config_entry user.name) email=$(get_config_entry user.email)

  if [ -f "$path" ]; then
    if [ -f "$path.bak" ]; then
      notice "Un fichier $path.bak existait déjà : je n’y touche pas."
    else
      mv -n "$path" "$path.bak" && notice "Votre $path a été sauvegardé dans $path.bak"
    fi
  fi
  notice "Recalage de $path sur notre configuration conseillée…"
  echo "$contents" > "$path"

  notice "Restauration / définition de votre identité…"
  ensure_value user.name "$username" "Votre nom complet"
  ensure_value user.email "$email" "Votre e-mail"

  if [ -f "$path.bak" ]; then
    notice "Fusion de vos réglages existants que nous n’aurions pas (re)défini…"
    git config -f "$path.bak" --list | {
      IFS==
      while read name value; do
        merge_value "$name" "$value"
      done
    }
  fi

  ok '\n\\o/ Configuration globale terminée !\n'
}

function ensure_prompt()
{
  announce "Personnalisation du prompt (Bash uniquement)"

  local file=$(get_proper_bash_config_file)
  local contents=$(curl -s "$PROMPT_GIST_RAW_URL" | grep -v '^#\|^$')

  notice 'Mise en commentaire des anciennes variables d’environnement Git et PS1…'
  sed $sed_inplace $sed_extended 's/^export (GIT_|PS1)/\n### Commented by Git Attitude Config Script\n# export \1/g' "$file"

  notice 'Ajout des nouvelles définitions…'
  echo '' >> "$file"
  echo "$contents" >> "$file"

  source "$file"

  if [ 'function' = "$(type -t __git_ps1)" ]; then
    notice 'Une définition de prompt pour Git (__git_ps1) est déjà présente : je n’y touche pas.'
  else
    local paths=$(get_proper_git_ps1_file)
    if [ -n "$paths" ]; then
      local latest_file=$(echo "$paths" | tail -n 1)
      notice "Chargement des définitions de prompt pour Git depuis ${latest_file}…"
      echo -e "\n# Git completion and prompt definitions" >> "$file"
      echo "$paths" | while read -r path; do
        echo "source '$path'" >> "$file"
      done
    else
      ko 'Impossible de trouver une source de prompt/complétion Git :-(\n'
      return
    fi
  fi

  ok '\n\\o/ Configuration du prompt terminée !\n'
}

function ensure_value()
{
  local value="$2"
  while [ -z "$value" ]; do
    echo -n "$3 doit être renseigné : " >&2
    read -r value >&2
  done
  git config --global "$1" "$value"
}

function get_config_entry()
{
  git config --global --get "$1" 2> /dev/null
}

function get_local_config_path()
{
  local default="$HOME/.gitconfig"
  [ -f "$default" ] && echo "$default" && return

  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
  [ -f "$xdg" ] && echo "$xdg" || echo "$default"
}

function get_proper_bash_config_file()
{
  for option in .bashrc .bash_profile .profile; do
    [ -f "$HOME/$option" ] && echo "$HOME/$option" && return
  done
  if uname -s | grep -q Darwin; then
    echo "$HOME/.profile"
  else
    echo "$HOME/.bashrc"
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

config
