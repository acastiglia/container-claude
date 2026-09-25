# Container environment

- GitHub access uses a fine-grained token (GH_TOKEN) with limited repositories and permissions. No SSH keys are available.
- If a git or gh command fails with 403 or "permission denied", report it and stop. Do not change remotes, create SSH keys, or look for other credentials.
