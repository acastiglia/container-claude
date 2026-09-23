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
