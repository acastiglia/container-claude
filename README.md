# Claude Code in Docker

Runs [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) in a Docker container, one per workspace directory.

## Usage

```bash
alias claude='/path/to/claude.sh'
cd ~/projects/my-app
claude
```

- Use an alias, not a symlink: the script finds its `Dockerfile` relative to its own path.
- The first run offers to build the `claude-code` image.
- The current directory is mounted at `/src`.
- If the directory has stopped containers, you can resume one (Enter picks the newest) or start a new one. Running containers are never reused.
- `/root/.claude` (login, settings, memory) is a shared volume, so it persists across containers and rebuilds.
- `~/.claude/CLAUDE.md` and `~/.claude/agents` are mounted read-only as the global memory file and agents directory, if they exist.
- Detach with `Ctrl-P Ctrl-Q`; reattach with `docker attach <container>`. Exiting Claude Code leaves a bash shell, and exiting that stops the container.

The memory file is mounted as a single file, so editors that save by replacing the file break the mount. In Vim:

```vim
autocmd BufWritePre */.claude/CLAUDE.md setlocal backupcopy=yes
```

## Options

| Option                     | Description                                                                         |
|----------------------------|-------------------------------------------------------------------------------------|
| `-s`, `--shell`            | Open bash instead of Claude Code. Running containers are offered too.              |
| `-r`, `--rebuild`          | Rebuild the image with the latest Claude Code release, then continue.              |
| `-m`, `--memory-file FILE` | Mount `FILE` as the global `CLAUDE.md` instead of `~/.claude/CLAUDE.md`.            |
| `-a`, `--agents-dir DIR`   | Mount `DIR` as the global agents directory instead of `~/.claude/agents`.           |
| `-h`, `--help`             | Show help.                                                                          |

Mounts and the image are fixed when a container is created; changes apply to new containers only.

## Environment variables

| Variable               | Default                          | Description                                  |
|------------------------|----------------------------------|----------------------------------------------|
| `CLAUDE_IMAGE`         | `claude-code`                    | Image name, without a tag.                   |
| `CLAUDE_HOME_VOLUME`   | `claude-home`                    | Volume mounted at `/root/.claude`.           |
| `CLAUDE_MEMORY_FILE`   | `~/.claude/CLAUDE.md`            | Global memory file. Overridden by `-m`.      |
| `CLAUDE_AGENTS_DIR`    | `~/.claude/agents`               | Global agents directory. Overridden by `-a`. |
| `CLAUDE_WORKSPACE`     | Current directory                | Directory mounted at `/src`.                 |
| `CLAUDE_GH_TOKEN_FILE` | `~/.config/claude-code/gh-token` | GitHub token file.                           |

Defaults are skipped if missing; paths set explicitly must exist.

## GitHub access

SSH keys are not available in the container. Git and `gh` authenticate with a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) instead. SSH remotes for `github.com` are rewritten to HTTPS; other hosts do not authenticate.

Create the token with **Only select repositories** and these repository permissions, leaving everything else at **No access** (notably Workflows, Administration and Secrets):

| Permission      | Access                                   | Needed for                   |
|-----------------|------------------------------------------|------------------------------|
| Metadata        | Read-only                                | Everything                   |
| Contents        | Read-only, or Read and write to push     | `git` clone/fetch/pull/push  |
| Pull requests   | Read and write (optional)                | `gh pr`                      |
| Issues          | Read-only or Read and write (optional)   | `gh issue`                   |
| Actions         | Read-only (optional)                     | `gh run`                     |
| Commit statuses | Read-only (optional)                     | `gh pr checks`               |

A token covers one owner. Write access can't be limited by branch, so protect important branches with a [ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).

Save it on the host:

```bash
mkdir -p ~/.config/claude-code
printf '%s' 'github_pat_...' > ~/.config/claude-code/gh-token
chmod 600 ~/.config/claude-code/gh-token
```

The token's directory is mounted read-only into new containers, so keep nothing else in it. To rotate, overwrite the file and restart Claude Code.

`container-instructions.md` is baked into the image as the managed `CLAUDE.md`, telling Claude Code how GitHub access works and to stop on permission errors.
