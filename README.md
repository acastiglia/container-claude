# Claude Code in Docker

Runs [Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code) inside a Docker container, with one container per workspace directory.

`claude.sh` attaches to the running container for the current directory, offers to resume the most recently stopped one, or starts a new one. The current directory is mounted into the container at `/src`.

Each container is labelled with its workspace path, which is how `claude.sh` finds the right container for the current directory.

Login credentials, settings, and memory live in `/root/.claude` on a shared Docker volume, so they survive across containers and image rebuilds. Your own `~/.claude/CLAUDE.md` is mounted read-only as Claude Code's global `CLAUDE.md`, so the instructions you use on the host apply in every container. Use `--memory-file` to mount a different file.

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
| `-s`, `--shell`   | Open a bash shell in the container instead of Claude Code. Claude Code keeps running in the background.                             |
| `-r`, `--rebuild` | Rebuild the image with the latest Claude Code release, tagged as both `claude-code:<version>` and `claude-code:latest`. Existing containers keep the image they were created from. |
| `-m`, `--memory-file FILE` | Mount `FILE` read-only as the global `CLAUDE.md` in new containers instead of `~/.claude/CLAUDE.md`. Existing containers keep the memory file they were created with. |
| `-h`, `--help`    | Show help.                                                                                                                          |

### Detaching

Detach from an attached container with `Ctrl-P Ctrl-Q`. The container keeps running, and the next run of `claude.sh` in the same directory reattaches to it. If the screen stays blank after attaching, press Enter.

Exiting Claude Code drops you into a bash shell in the container; exiting that shell stops the container.

## Configuration

| Environment variable | Default              | Description                                                        |
|----------------------|----------------------|--------------------------------------------------------------------|
| `CLAUDE_IMAGE`       | `claude-code`        | Name of the Docker image to build and run.                         |
| `CLAUDE_HOME_VOLUME` | `claude-home`        | Docker volume mounted at `/root/.claude`.                          |
| `CLAUDE_MEMORY_FILE` | `~/.claude/CLAUDE.md` | File mounted read-only as the global `/root/.claude/CLAUDE.md`. Overridden by `--memory-file`. |
| `CLAUDE_WORKSPACE`   | Current directory    | Directory mounted at `/src` and used to identify the container.    |
| `CLAUDE_GH_TOKEN`    | Unset                | GitHub token passed to new containers as `GH_TOKEN`. See [GitHub access](#github-access). |

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

Export the token as `CLAUDE_GH_TOKEN` on the host, for example in your shell profile:

```bash
export CLAUDE_GH_TOKEN=github_pat_...
```

`claude.sh` passes it to new containers as `GH_TOKEN`, without putting it on the `docker run` command line. Containers that already exist keep the token they were created with, or have none if they were created without it, so start a new container after setting or rotating the token. Permission changes made to an existing token on GitHub apply immediately.

The token is stored in the container's configuration and is visible to anyone who can run `docker inspect` on the host.

### How it works

Git in the container uses `gh` as its credential helper for `https://github.com`, and `git@github.com:` and `ssh://git@github.com/` remotes are rewritten to HTTPS, so clones made on the host work as-is. Remotes on other hosts do not authenticate.

`container-instructions.md` is baked into the image as Claude Code's managed `CLAUDE.md` (`/etc/claude-code/CLAUDE.md`). It tells Claude Code how GitHub access works in the container and to stop rather than work around permission errors. It loads alongside your global `CLAUDE.md`, and changes take effect after `--rebuild`.
