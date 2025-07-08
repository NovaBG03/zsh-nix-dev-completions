# zsh-nix-dev-completions

A zsh plugin that dynamically manages completions for Nix development environments, automatically loading and unloading zsh and bash completions when entering/exiting nix shells.

## The Problem

When using Nix development environments (through `nix develop`, `nix shell`, `nix-shell`, or `direnv`), Nix adds the share directories of new packages to the `XDG_DATA_DIRS` environment variable. However, zsh doesn't automatically react to these changes, meaning that completions from newly available packages are not loaded into the current shell session.

### The Core Issue

1. **Nix adds paths**: When entering a nix shell, Nix adds `/nix/store/*/share` paths to `XDG_DATA_DIRS`
2. **Zsh doesn't react**: Zsh's completion system doesn't automatically scan these new paths
3. **Completions unavailable**: Tools available in the nix shell lack tab completion
4. **Manual intervention needed**: Users must manually run `compinit` or restart their shell

## How It Works

### Environment Monitoring

The plugin uses zsh's built-in hook system rather than listening for specific commands. It registers hooks with `precmd_functions` and `chpwd_functions` to monitor changes to the `XDG_DATA_DIRS` environment variable. This means it will detect changes regardless of how they occur - whether from `nix develop`, `nix shell`, `nix-shell`, `direnv`, or any other tool that modifies the environment.

### Change Detection and Processing

The plugin:

1. **Monitors XDG_DATA_DIRS**: Checks for changes before each prompt and when changing directories
2. **Filters nix store paths**: Only processes paths matching `/nix/store/*/share`
3. **Tracks changes**: Compares current nix store paths with previously known ones
4. **Calculates differences**: Determines which packages were added or removed

### Zsh Completion Management

**For removed packages**:

- Removes the completion directory from `fpath`
- Unloads completion functions
- Removes command mappings from `_comps`

**For added packages**:

- Checks if `${entry}/zsh/site-functions` directory exists
- If it exists, adds it to the beginning of `fpath`

### Bash Completion Handling

**For removed packages**:

- Looks up previously sourced bash completions
- Uses `compdef -d` to remove bash completion mappings
- Clears the tracking entry

**For added packages**:

- Only processes packages that don't have zsh completions
- Looks for bash completion scripts in `${entry}/bash-completion/completions`
- For each script, checks if a zsh completion function already exists
- If no zsh function exists, sources the bash completion script
- Tracks which commands got bash completions

### Completion System Rebuild

After processing all changes, the plugin rebuilds the completion system using a unique cache identifier based on the current `fpath`.

## Installation

### Manual Installation

```bash
git clone https://github.com/NovaBG03/zsh-nix-dev-completions.git ~/.zsh/zsh-nix-dev-completions
echo 'source ~/.zsh/zsh-nix-dev-completions/plugin.zsh' >> ~/.zshrc
```

### Home Manager Integration

If you're using [Home Manager](https://github.com/nix-community/home-manager), you can install the plugin by adding it to your `home.nix`:

```nix
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    plugins = [
      {
        name = "zsh-nix-dev-completions";
        src = pkgs.fetchFromGitHub {
          owner = "NovaBG03";
          repo = "zsh-nix-dev-completions";
          rev = "main"; # or specific commit/tag
          sha256 = ""; # add the correct sha256 hash
        };
        file = "plugin.zsh";
      }
    ];
  };
}
```

## Usage

Once installed, the plugin works automatically. When you enter a nix development environment, you'll see logging output indicating what the plugin is doing:

```

nix-dev-completions: 🔄 Environment changed, updating completions...
nix-dev-completions: 📊 Changes detected - adding 2, removing 0 packages
nix-dev-completions: ✅ zsh found package-name
nix-dev-completions: ❌ zsh none other-package
nix-dev-completions: ✅ bash found command-name (other-package)
nix-dev-completions: 🔧 Rebuilding completion system (cache: zcompdump-a1b2c3d4-5.8)

```

## Limitations and Known Issues

### Current Limitations

- **No zsh-autosuggestions integration**: The plugin doesn't currently integrate with zsh-autosuggestions
- **Not tested in every scenario**: The plugin may not handle all edge cases correctly
- **Bash completion versioning conflicts**: If you have bash completions for a tool (e.g., node) and then load a dev shell with a different version of that tool, the original bash completions will still be used instead of the new version's completions

### Example Issue

If you have Node.js installed system-wide with bash completions, and then enter a nix shell with a different version of Node.js, the system's bash completions for Node.js will continue to be used rather than the completions from the nix shell version.

## Inspiration

This plugin draws inspiration from [zsh-completion-sync](https://github.com/BronzeDeer/zsh-completion-sync), which provides a more general solution for completion synchronization.

## Related Issues

This plugin addresses several long-standing issues in the Nix and shell completion ecosystem:

- [zsh-autocomplete #755](https://github.com/marlonrichert/zsh-autocomplete/issues/755) - Completions not working with nix develop
- [direnv #443](https://github.com/direnv/direnv/issues/443) - Shell completion integration
- [direnv #1373](https://github.com/direnv/direnv/issues/1373) - Completion handling in nix shells

## Status

⚠️ **Work in Progress** ⚠️

This plugin is currently an experiment. While it provides functional completion management for nix development environments, I'm open to suggestions and help with fixing issues and improvements.

### Future Improvements

- **Better bash completion tracking**: Track which bash completions are sourced and allow removing them to source different versions when `XDG_DATA_DIRS` changes
- **zsh-autosuggestions integration**: Better integration with popular zsh plugins
- **Enhanced error handling**: More robust handling of edge cases and malformed completion scripts

## Contributing

If you encounter problems or have ideas for improvements, please:

1. Open an issue describing the problem or suggestion
2. Provide details about your environment (zsh version, nix version, etc.)
3. Include any relevant error messages or unexpected behavior
