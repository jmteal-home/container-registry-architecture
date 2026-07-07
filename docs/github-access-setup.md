# GitHub Access Setup

How to connect every Claude/Terminal surface to this repository so it works
**without any per-session interaction**. Each surface needs exactly **one**
one-time authorization; after that it's hands-off.

The tools collapse into **three auth domains**:

| Domain | Covers | One-time setup |
|---|---|---|
| Anthropic cloud | Claude Code on the web + Dispatch/routines | Claude GitHub App (authorized once at [claude.ai/code](https://claude.ai/code)) |
| Your Mac | Terminal + local Claude Code CLI | SSH key in the macOS Keychain |
| Cowork connector | Claude Cowork | GitHub connector in Claude → Settings → Connectors |

A [`SessionStart` hook](../.claude/hooks/session-start.sh) verifies GitHub
connectivity non-interactively at the start of every Claude Code session, so a
missing credential surfaces as a clear message instead of a hang.

---

## 1. Anthropic cloud — Claude Code on the web + Dispatch/routines

Cloud sessions authenticate through an Anthropic-managed proxy; your token never
enters the container. This is configured once at the account level via the
**Claude GitHub App** (browser onboarding at [claude.ai/code](https://claude.ai/code))
or by running `/web-setup` in a local terminal to sync your `gh` token.

A cloud session can reach any repository the connected GitHub account can see,
so this single connection covers Code-on-web **and** Dispatch/scheduled routines.
No per-session action.

## 2. Your Mac — Terminal + local Claude Code CLI (SSH key)

Both use your local git, so one SSH key covers both. Run once on your Mac:

```bash
# 1. Generate a dedicated GitHub key
ssh-keygen -t ed25519 -C "james.teal@jmteal.com" -f ~/.ssh/id_ed25519_github

# 2. Wire it into ssh + the macOS Keychain so it loads automatically, forever
cat >> ~/.ssh/config <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  AddKeysToAgent yes
  UseKeychain yes
EOF

# 3. Store it in your login Keychain now
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github

# 4. Copy the PUBLIC key to your clipboard
pbcopy < ~/.ssh/id_ed25519_github.pub
```

Then the **one browser step**: open <https://github.com/settings/ssh/new>, paste
the public key, and save. Verify and point your local clone at SSH:

```bash
ssh -T git@github.com     # expect: "Hi <you>! You've successfully authenticated..."

# in your LOCAL clone (not a cloud session container):
git remote set-url origin git@github.com:jmteal-home/container-registry-architecture.git
```

With `UseKeychain yes`, a key passphrase (if set) is requested at most once and
then remembered by the Keychain. Set an empty passphrase in step 1 for a fully
unattended key.

> Do not change the git remote inside a Claude cloud session container — it
> correctly uses the internal proxy remote.

## 3. Claude Cowork (only if you use it)

Cowork reaches GitHub through **Connectors**, separate from the code integration.
In Claude, go to **Settings → Connectors → add GitHub** (Composio Connect or
GitHub's remote MCP server) and approve the scopes in the browser. After that,
Cowork operates on the repo with no per-task auth.

---

## Result

Once the three authorizations above are done, every surface connects with **no
ongoing interaction**:

| Tool | Connection | Ongoing interaction |
|---|---|---|
| Terminal (Mac) | SSH key + Keychain | none |
| Claude Code — local CLI | same SSH key | none |
| Claude Code — web | Claude GitHub App | none |
| Dispatch / routines | same cloud connection | none |
| Cowork | GitHub connector | none |

## References

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
- [Use the GitHub integration — Claude Help Center](https://support.claude.com/en/articles/10167454-use-the-github-integration)
- [Connect GitHub to Claude Cowork](https://composio.dev/toolkits/github/framework/claude-cowork)
