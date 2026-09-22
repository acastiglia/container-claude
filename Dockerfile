FROM node:22-alpine
LABEL app=claude-code
WORKDIR /src
RUN apk add --no-cache bash
ENV SHELL=/bin/bash
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
CMD ["bash", "-c", "claude; exec bash"]
