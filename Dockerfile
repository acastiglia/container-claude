FROM node:22-alpine
LABEL app=claude-code
WORKDIR /src
RUN apk add --no-cache bash
RUN apk add --no-cache git
RUN apk add --no-cache github-cli
RUN git config --system credential.https://github.com.helper '!gh auth git-credential' \
 && git config --system --add url.https://github.com/.insteadOf git@github.com: \
 && git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/
ENV SHELL=/bin/bash
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
COPY container-instructions.md /etc/claude-code/CLAUDE.md
CMD ["bash", "-c", "claude; exec bash"]
