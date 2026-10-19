# BayanihanHub Agent Guidelines & Rules

## Repository & Version Control Rules
- **Automatic Push**: Commit and push every approved change and task completion to the remote repository (`origin/main`) so the user's GitHub repository is always up-to-date with all project modifications.
- **Security & Secret Hygiene**: Never commit sensitive information, secrets, API keys, passwords, or `.env` files. Ensure `.gitignore` continues to exclude `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.test`, `.env.*`, `node_modules/`, `venv/`, `backend/.venv`, `.env.example`, `.env.example.local`, `.env.example.development`, `.env.example.production`, `.env.example.test`, `.env.example.*` files, virtual environments, build artifacts, and local configurations.
### Continuous Git Sync Protocol
- Maintain an internal counter of edited/created/deleted files during your task execution.
- Every time you modify or generate 2 files, run a terminal command before proceeding:
  ```bash
  git add -A && git commit -m "chore(auto): update changed files" && git push origin HEAD
