# Claude Code in Docker

Runs [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) inside a Docker container, with one container per workspace directory.

`claude.sh` starts a Claude Code container for the current directory. If the directory has stopped containers, it lists them, newest first, and lets you resume one or start a new one; pressing Enter resumes the newest. Running containers are left alone, so each run starts a separate Claude Code session. The current directory is mounted into the container at `/src`.

Each container is labelled with its workspace path, which is how `claude.sh` finds the right container for the current directory.

Login credentials, settings, and memory live in `/root/.claude` on a shared Docker volume, so they survive across containers and image rebuilds. Your own `~/.claude/CLAUDE.md`, if it exists, is mounted read-only as Claude Code's global `CLAUDE.md`, so the instructions you use on the host apply in every container. Use `--memory-file` to mount a different file.

The memory file is mounted as a single file, so running containers only see edits that rewrite it in place. Editors that save by writing a new file and renaming it over the old one break the mount until the container is recreated. In Vim, keep edits in place with:
 
```vim
autocmd BufWritePre */.claude/CLAUDE.md setlocal backupcopy=yes
```

## Usage

Run the script from the directory you want Claude Code to work in:

```bash
cd ~/projects/my-app
/path/to/claude.sh
```

To call it as `claude` from anywhere, add an alias rather than a symlink, since the script locates the `Dockerfile` relative to its own path:

```bash
alias claude='/path/to/claude.sh'
```

On first run, the script offers to build the `claude-code` image with the latest Claude Code release.

### Options

| Option            | Description                                                                                                                         |
|-------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| `-s`, `--shell`   | Open a bash shell in the container instead of Claude Code. Claude Code keeps running in the background. Running containers are also offered, so you can open a shell alongside an existing session. |
| `-r`, `--rebuild` | Offer to rebuild the image with the latest Claude Code release, tagged as both `claude-code:<version>` and `claude-code:latest`, then continue. Existing containers keep the image they were created from. |
| `-m`, `--memory-file FILE` | Mount `FILE` read-only as the global `CLAUDE.md` in new containers instead of `~/.claude/CLAUDE.md`. Only mounted if the file exists, unless given explicitly, in which case a missing file is an error. Existing containers keep the memory file they were created with. |
| `-a`, `--agents-dir DIR` | Mount `DIR` read-only as the global agents directory (`/root/.claude/agents`) in new containers instead of `~/.claude/agents`. Only mounted if the directory exists, unless given explicitly, in which case a missing directory is an error. Existing containers keep the agents directory they were created with. |
| `-h`, `--help`    | Show help.                                                                                                                          |

### Detaching

Detach from an attached container with `Ctrl-P Ctrl-Q`. The container keeps running, but `claude.sh` does not reattach to running containers. Reattach with `docker attach <container>`, and press Enter if the screen stays blank.

Exiting Claude Code drops you into a bash shell in the container; exiting that shell stops the container.

## Configuration

| Environment variable | Default              | Description                                                        |
|----------------------|----------------------|--------------------------------------------------------------------|
| `CLAUDE_IMAGE`       | `claude-code`        | Name of the Docker image to build and run, without a tag.          |
| `CLAUDE_HOME_VOLUME` | `claude-home`        | Docker volume mounted at `/root/.claude`.                          |
| `CLAUDE_MEMORY_FILE` | `~/.claude/CLAUDE.md` | File mounted read-only as the global `/root/.claude/CLAUDE.md`. The default is mounted only if it exists; a file set here must exist. Overridden by `--memory-file`. |
| `CLAUDE_AGENTS_DIR`  | `~/.claude/agents`    | Directory mounted read-only as the global `/root/.claude/agents`. The default is mounted only if it exists; a directory set here must exist. Overridden by `--agents-dir`. |
| `CLAUDE_WORKSPACE`   | Current directory    | Directory mounted at `/src` and used to identify the container.    |
| `CLAUDE_GH_TOKEN_FILE` | `~/.config/claude-code/gh-token` | File holding the GitHub token for new containers. The default is used only if it exists; a file set here must exist. See [GitHub access](#github-access). |

## GitHub access

Your SSH keys are not available in the container. Instead, git and `gh` in the container authenticate to GitHub with a fine-grained personal access token that you provide.

### Creating the token

1. Open [New fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) on GitHub.
2. Set **Resource owner** to the account or organization that owns the repositories. A token covers one owner, so repositories across several organizations need separate tokens. Some organizations require an admin to approve the token.
3. Under **Repository access**, choose **Only select repositories** and pick the repositories Claude Code should reach. Public repositories can be pulled without being selected.
4. Under **Repository permissions**, grant:

   | Permission    | Access                                               | Needed for                              |
   |---------------|------------------------------------------------------|-----------------------------------------|
   | Metadata      | Read-only (selected automatically)                   | Everything                              |
   | Contents      | Read-only to pull and fetch, Read and write to push  | `git clone`, `fetch`, `pull`, `push`    |
   | Pull requests | Read and write (optional)                            | `gh pr create`, `comment`, `merge`      |
   | Issues        | Read-only or Read and write (optional)               | `gh issue` commands                     |
   | Actions       | Read-only (optional)                                 | `gh run list`, `gh run view`            |
   | Commit statuses | Read-only (optional)                               | `gh pr checks`                          |

   Leave everything else, including all account permissions, at **No access**. In particular, leave **Workflows** off so that GitHub rejects pushes that change `.github/workflows/`, and leave **Administration** and **Secrets** off so the container cannot change repository settings or read secrets.

The selected permissions apply to every selected repository. Write access cannot be limited to particular branches, so protect important branches with a [ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) that blocks force-pushes and deletion.

### Providing the token

Save the token to `~/.config/claude-code/gh-token` on the host, readable only by you:

```bash
mkdir -p ~/.config/claude-code
printf '%s' 'github_pat_...' > ~/.config/claude-code/gh-token
chmod 600 ~/.config/claude-code/gh-token
```

Set `CLAUDE_GH_TOKEN_FILE` to use a different file.

`claude.sh` mounts the directory holding the token file read-only at `/run/secrets/claude-code` in new containers, and sets `GH_TOKEN_FILE` to the file's path there. Everything else in that directory is visible to the container too, so keep the token in a directory of its own. The token itself is not in the container's configuration, so `docker inspect` does not show it.

The directory is mounted rather than the file, so the container sees the token file however it is saved, including by editors that replace it. Containers created without a token file have no mount; start a new container after creating it.

### Rotating the token

Overwrite the token file on the host. In the container, the token is read when Claude Code starts and whenever an interactive bash shell starts, so restart Claude Code to pick up the new token. Shells opened with `--shell` afterwards use it straight away. Permission changes made to an existing token on GitHub apply immediately.

### How it works

`gh-token.sh` is baked into the image at `/etc/bash/gh-token.sh`. It exports the contents of `$GH_TOKEN_FILE` as `GH_TOKEN`, which `gh` reads. The container's command sources it before starting Claude Code, and Alpine's bash sources it in every interactive shell.

Git in the container uses `gh` as its credential helper for `https://github.com`, and `git@github.com:` and `ssh://git@github.com/` remotes are rewritten to HTTPS, so clones made on the host work as-is. Remotes on other hosts do not authenticate.

`container-instructions.md` is baked into the image as Claude Code's managed `CLAUDE.md` (`/etc/claude-code/CLAUDE.md`). It tells Claude Code how GitHub access works in the container and to stop rather than work around permission errors. It loads alongside your global `CLAUDE.md`, and changes take effect after `--rebuild`.
