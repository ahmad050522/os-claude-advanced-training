#!/usr/bin/env bash
# One-command setup for "We're All Software Developers Now" on a Mac.
#
# It does Session 1's setup and Session 2's "get your copy" steps for you, in order,
# using the same commands as docs/install-github-cli.md and docs/install-claude-code.md:
#   1. Git (Apple's command line tools)
#   2. Homebrew, then the GitHub CLI (gh)
#   3. Claude Code
#   4. Signs you in to GitHub (you approve it in your browser)
#   5. Tells Git your name and Opensend email
#   6. Makes your fork, downloads it to ~/os-claude-advanced-training, makes your branch
#   7. Runs the setup check
#
# Anything already done is skipped, so it's safe to run again.
# It never sees your passwords or one-time codes: you type those yourself when asked.
#
# Run it in Terminal:
#   curl -fsSL https://raw.githubusercontent.com/fueled-io/os-claude-advanced-training/main/install.sh | bash
# or, from a downloaded copy:
#   bash install.sh

UPSTREAM="fueled-io/os-claude-advanced-training"
REPO_NAME="os-claude-advanced-training"
REPO_DIR="${INSTALL_REPO_DIR:-$HOME/$REPO_NAME}"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()   { printf '  OK    %s\n' "$1"; }
doing(){ printf '  ...   %s\n' "$1"; }
note() { printf '  NOTE  %s\n' "$1"; }
stop() {
  printf '\n  STOP  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
  printf '\n  Fix that, then run this installer again. It picks up where it left off.\n'
  printf '  Stuck? Send Sean Larkin a Slack message with what you see above.\n'
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
ask() { # ask "Question" default -> answer in $REPLY
  local q="$1" d="${2:-}"
  if [ -n "$d" ]; then printf '  %s [%s]: ' "$q" "$d"; else printf '  %s: ' "$q"; fi
  read -r REPLY || REPLY=""
  [ -z "$REPLY" ] && REPLY="$d"
}

install_git() {
  step "1. Git"
  # On a Mac, /usr/bin/git exists even before the tools are installed, so check the tools instead.
  if xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    ok "$(git --version)"; return
  fi
  doing "Installing Apple's command line tools, which include Git."
  note  "A window pops up: click Install and wait. It's a big download (often 10 to 30 minutes)."
  xcode-select --install >/dev/null 2>&1
  local waited=0
  until xcode-select -p >/dev/null 2>&1; do
    sleep 10; waited=$((waited + 10))
    [ $((waited % 120)) -eq 0 ] && doing "Still waiting for the install window to finish ($((waited / 60)) min)..."
    [ "$waited" -ge 5400 ] && stop "The command line tools didn't finish installing." "See docs/install-github-cli.md step 3."
  done
  git --version >/dev/null 2>&1 || stop "Git still isn't working after the install." "See docs/install-github-cli.md step 3."
  ok "$(git --version)"
}

load_brew() { # Homebrew's "Next steps": make brew work now, and in every new terminal.
  local b=""
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && { b="$p"; break; }; done
  [ -z "$b" ] && return 1
  eval "$("$b" shellenv)"
  local line="eval \"\$($b shellenv)\""
  if ! grep -qsF "$line" "$HOME/.zprofile"; then
    { echo; echo "$line"; } >> "$HOME/.zprofile"
    doing "Added Homebrew to ~/.zprofile so new terminals find it."
  fi
}

install_gh() {
  step "2. GitHub CLI (gh)"
  have brew || load_brew
  if have gh; then ok "$(gh --version | head -1)"; return; fi
  if ! have brew; then
    doing "Installing Homebrew first (from https://brew.sh)."
    note  "It asks for your Mac password. Nothing shows while you type it. That's normal."
    note  "When it says 'Press RETURN/ENTER to continue', press Return."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || stop "Homebrew didn't install." "See docs/install-github-cli.md step 4."
    load_brew || stop "Homebrew installed, but this terminal can't find it." "Open a new terminal window and run this installer again."
  fi
  ok "$(brew --version | head -1)"
  doing "brew install gh"
  brew install gh || stop "The GitHub CLI didn't install." "See docs/install-github-cli.md step 4."
  ok "$(gh --version | head -1)"
}

install_claude() {
  step "3. Claude Code"
  export PATH="$HOME/.local/bin:$PATH"
  if have claude; then ok "$(claude --version 2>/dev/null | head -1)"; else
    doing "Installing Claude Code. It shows no progress while it downloads; wait for it."
    curl -fsSL https://claude.ai/install.sh | bash || stop "Claude Code didn't install." "See docs/install-claude-code.md step 2."
    have claude || stop "Claude Code installed, but this terminal can't find it." "See docs/install-claude-code.md step 3."
    ok "$(claude --version 2>/dev/null | head -1)"
  fi
  # Anthropic's PATH fix (docs/install-claude-code.md step 3), so new terminals find claude too.
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if [ -x "$HOME/.local/bin/claude" ] && ! grep -qsF "$line" "$HOME/.zshrc"; then
    echo "$line" >> "$HOME/.zshrc"
    doing "Added Claude Code to ~/.zshrc so new terminals find it."
  fi
  note "Claude Desktop isn't installed by this script: download it from https://claude.com/download"
}

sign_in() {
  step "4. Sign in to GitHub"
  if gh auth status >/dev/null 2>&1; then ok "Signed in as $(gh api user --jq .login 2>/dev/null)"; return; fi
  note "It shows a one-time code. Copy it, press Enter, paste it into the browser page, and approve."
  note "If it asks anything else, press Enter to take the default."
  gh auth login --hostname github.com --git-protocol https --web \
    || stop "GitHub sign-in didn't finish." "See docs/install-github-cli.md step 5."
  gh auth status >/dev/null 2>&1 || stop "GitHub sign-in didn't finish." "See docs/install-github-cli.md step 5."
  ok "Signed in as $(gh api user --jq .login 2>/dev/null)"
}

git_identity() {
  step "5. Tell Git who you are"
  local name email
  name="$(git config --global user.name)"
  email="$(git config --global user.email)"
  if [ -z "$name" ]; then
    ask "Your first and last name (for example: Alex Kim)"; name="$REPLY"
    [ -z "$name" ] && stop "Git needs your name." "Run this installer again and type it when asked."
    git config --global user.name "$name"
  fi
  case "$email" in
    *@opensend.com) ;;
    *)
      [ -n "$email" ] && note "Git's email is $email. The series uses your Opensend email."
      ask "Your Opensend email (for example: alex@opensend.com)" "$email"; email="$REPLY"
      [ -z "$email" ] && stop "Git needs your email." "Run this installer again and type it when asked."
      git config --global user.email "$email"
      ;;
  esac
  ok "Name: $(git config --global user.name)"
  ok "Email: $(git config --global user.email)"
}

get_repo() {
  step "6. Your copy of the repo"
  if [ -d "$REPO_DIR/.git" ]; then
    ok "Already downloaded: $REPO_DIR"
  elif [ -e "$REPO_DIR" ]; then
    stop "$REPO_DIR already exists but isn't a copy of the repo." "Move or rename that folder, then run this again."
  else
    doing "Making your fork on GitHub and downloading it to $REPO_DIR"
    note  "Your fork is public, like Opensend's repo. See CONTRIBUTING.md before your first commit."
    (cd "$(dirname "$REPO_DIR")" && gh repo fork "$UPSTREAM" --clone -- "$(basename "$REPO_DIR")") \
      || stop "Making or downloading your fork didn't work." "See README.md, 'Get your copy of the repo'."
    ok "Downloaded: $REPO_DIR"
  fi
  cd "$REPO_DIR" || stop "Can't open $REPO_DIR."

  local branch suggested
  branch="$(git branch --show-current)"
  if [ -n "$branch" ] && [ "$branch" != main ] && [ "$branch" != master ]; then
    ok "On your branch: $branch"; return
  fi
  suggested="$(git config user.name | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  ask "Name for your branch: first-last, lowercase" "$suggested"; branch="$REPLY"
  [ -z "$branch" ] && stop "Your branch needs a name." "Run this installer again and type it when asked."
  # Use the branch if it exists here or on your fork already; otherwise make it.
  git switch "$branch" 2>/dev/null || git switch -c "$branch" || stop "Couldn't make your branch '$branch'."
  ok "On your branch: $branch"
}

check() {
  step "7. Setup check"
  bash .claude/skills/check-setup/scripts/check-setup.sh
}

main() {
  # When run as `curl ... | bash`, the keyboard isn't connected to this script. Reconnect it,
  # so questions and the GitHub sign-in can be answered.
  if [ ! -t 0 ] && (exec </dev/tty) 2>/dev/null; then exec </dev/tty; fi

  printf '\033[1mSetup for %s\033[0m\n' "$REPO_NAME"
  [ "$(uname -s)" = Darwin ] || stop "This installer is for a Mac." "On Windows, use install.ps1 (see README.md)."

  install_git
  install_gh
  install_claude
  sign_in
  git_identity
  get_repo
  check

  printf '\n\033[1mDone.\033[0m Close this terminal and open a new one, then:\n'
  printf '  cd %s\n  claude\n' "${REPO_DIR/#$HOME/~}"
  printf 'The first time, sign in with your Opensend Claude account and say yes to trusting the folder.\n'
}

main "$@"
