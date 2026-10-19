# BayanihanHub Agent Guidelines & Rules

## Repository & Version Control Rules
- **Automatic Push**: Commit and push every approved change and task completion to the remote repository (`origin/main`) so the user's GitHub repository is always up-to-date with all project modifications.
- **Security & Secret Hygiene**: Never commit sensitive information, secrets, API keys, passwords, or `.env` files. Ensure `.gitignore` continues to exclude `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.test`, `.env.*`, `node_modules/`, `venv/`, `backend/.venv`, `.env.example`, `.env.example.local`, `.env.example.development`, `.env.example.production`, `.env.example.test`, `.env.example.*` files, virtual environments, build artifacts, and local configurations.
## Git Commit Rules

When committing changes, **create separate commits per file**. Do NOT bundle multiple file changes into a single commit. Each file gets its own commit with a descriptive message specific to that file's changes.

For example, if `README.md`, `best-practice/claude-subagents.md`, and a skill file all changed:
- Commit 1: `git add README.md` → commit with README-specific message
- Commit 2: `git add best-practice/claude-subagents.md` → commit with subagents-doc-specific message
- Commit 3: `git add .claude/skills/weather-fetcher/SKILL.md` → commit with skill-specific message

This makes the git history cleaner and easier to review, revert, or cherry-pick individual changes.
