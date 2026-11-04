if [[ -n "${GH_TOKEN_FILE:-}" && -r "$GH_TOKEN_FILE" ]]; then
  GH_TOKEN="$(<"$GH_TOKEN_FILE")"
  export GH_TOKEN
fi
