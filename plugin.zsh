# zsh-nix-dev-completions
# A zsh plugin that dynamically manages completions for nix develop environments
# Automatically loads/unloads zsh and bash completions from nix store paths in XDG_DATA_DIRS
# as you enter/exit nix shells with direnv

# ===== PLUGIN IMPLEMENTATION =====

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Track last known state of environment variables
_LAST_XDG_DATA_DIRS=""
_LAST_NIX_STORE_DATA_DIRS=()

# Track bash completions: key=store_path, value=space-separated commands
typeset -gA _BASH_COMPLETIONS_BY_STORE_PATH

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Centralized logging function with consistent prefix
_nix_dev_completions_log() {
  echo "nix-dev-completions: $*"
}

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

# Main hook function - called on precmd and chpwd
_completion_sync:hook() {
  # Early return if no changes detected
  if [[ "$_LAST_XDG_DATA_DIRS" == "$XDG_DATA_DIRS" ]]; then
    return
  fi
  
  _nix_dev_completions_log "🔄 Environment changed, updating completions..."
  _LAST_XDG_DATA_DIRS=$XDG_DATA_DIRS;

  local nix_store_data_dirs=();
  for entry in ${(s/:/)XDG_DATA_DIRS}; do
    if [[ "$entry" == /nix/store/*/share ]]; then
      nix_store_data_dirs+=("$entry")
    fi
  done

  if [[ "$_LAST_NIX_STORE_DATA_DIRS" == "$nix_store_data_dirs" ]]; then
    _nix_dev_completions_log "📦 Nix store paths unchanged, skipping update"
    return
  fi

  local added=( ${nix_store_data_dirs:|_LAST_NIX_STORE_DATA_DIRS} )
  local removed=( ${_LAST_NIX_STORE_DATA_DIRS:|nix_store_data_dirs} )

  _nix_dev_completions_log "📊 Changes detected - adding ${#added[@]}, removing ${#removed[@]} packages"

  _nix_dev_completions_log "🗂️  Current bash completions map:"
  for key in "${(@k)_BASH_COMPLETIONS_BY_STORE_PATH}"; do
    _nix_dev_completions_log "   $key → ${_BASH_COMPLETIONS_BY_STORE_PATH[$key]}"
  done

  # Process removed packages
  for entry in "${removed[@]}"; do
    local package_name="${${entry#/nix/store/}%/share}"
    
    entry_zsh_completions_dir="${entry}/zsh/site-functions"
    local idx="$fpath[(Ie)$entry_zsh_completions_dir]"
    if (( $idx != 0 )); then
      fpath[$idx]=()
      
      # Unload zsh completion functions
      for comp_file in "$entry_zsh_completions_dir"/_*; do
        if [[ -f "$comp_file" ]]; then
          local func_name="${comp_file:t}"
          local cmd_name="${func_name#_}"
          _nix_dev_completions_log "🗑️ zsh remove $cmd_name ($package_name)"
          unfunction "$func_name" 2>/dev/null
          unset "_comps[$cmd_name]"
        fi
      done
    fi
    
    # Remove bash completions that were sourced from this store path
    if [[ -v "_BASH_COMPLETIONS_BY_STORE_PATH[$entry]" ]]; then
      local bash_commands=(${(s: :)_BASH_COMPLETIONS_BY_STORE_PATH[$entry]})
      for cmd in "${bash_commands[@]}"; do
        _nix_dev_completions_log "🗑️ bash remove $cmd ($package_name)"
        compdef -d "$cmd" 2>/dev/null
      done
      unset "_BASH_COMPLETIONS_BY_STORE_PATH[$entry]"
    fi
  done

  # Process added packages
  for entry in "${added[@]}"; do
    local package_name="${${entry#/nix/store/}%/share}"
    
    entry_zsh_completions_dir="${entry}/zsh/site-functions"
    if [[ -d "$entry_zsh_completions_dir" ]]; then
      _nix_dev_completions_log "✅ zsh found $package_name"
      fpath=("$entry_zsh_completions_dir" $fpath)
    else
      _nix_dev_completions_log "❌ zsh none  $package_name"
    fi
  done


  # Rebuild completion system with new fpath
  nix_zcompdump_id=$(echo "${(j/:/)fpath}" | sha256sum | cut -d' ' -f1 | cut -c1-8)
  _nix_dev_completions_log "🔧 Rebuilding completion system (cache: zcompdump-$nix_zcompdump_id-$ZSH_VERSION)"
  autoload -Uz compinit && compinit -C -d "$XDG_CACHE_HOME"/zsh/zcompdump-$nix_zcompdump_id-$ZSH_VERSION

  # Source bash completions for newly added packages without zsh completions
  for entry in "${added[@]}"; do
    local package_name="${${entry#/nix/store/}%/share}"
    entry_bash_completions_path="${entry}/bash-completion/completions"
    
    if [[ -d "$entry_bash_completions_path" ]]; then
      local sourced_commands=()
      
      for completion_script in "$entry_bash_completions_path"/*; do
        if [[ -f "$completion_script" ]]; then
          command_name="${$(basename "$completion_script")%.*}"
          zsh_completion_func="_${command_name}"
          
          if ! type "$zsh_completion_func" &>/dev/null; then
            _nix_dev_completions_log "✅ bash found $command_name ($package_name)"
            source "$completion_script"
            sourced_commands+=("$command_name")
          else
            _nix_dev_completions_log "❌ bash skip  $command_name ($package_name)"
          fi
        fi
      done
      
      # Store the commands that got bash completions from this store path
      if (( ${#sourced_commands[@]} > 0 )); then
        _BASH_COMPLETIONS_BY_STORE_PATH[$entry]="${(j: :)sourced_commands}"
      fi
    fi
  done

  _LAST_NIX_STORE_DATA_DIRS=("${nix_store_data_dirs[@]}")
  _nix_dev_completions_log "---"
}

# =============================================================================
# PLUGIN INITIALIZATION
# =============================================================================

# Register hooks to monitor environment changes
_nix_dev_completions_log "🚀 Initializing dynamic completion management..."

typeset -ag precmd_functions
if (( ! ${precmd_functions[(I)_completion_sync:hook]} )); then
  precmd_functions=($precmd_functions _completion_sync:hook)
  _nix_dev_completions_log "   ↳ Registered precmd hook (monitors environment before each prompt)"
fi

typeset -ag chpwd_functions
if (( ! ${chpwd_functions[(I)_completion_sync:hook]} )); then
  chpwd_functions=($chpwd_functions _completion_sync:hook)
  _nix_dev_completions_log "   ↳ Registered chpwd hook (monitors environment on directory changes)"
fi

_nix_dev_completions_log "✅ Ready to manage completions for nix develop environments"
