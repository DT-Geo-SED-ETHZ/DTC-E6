# Contributing to dtgeofinder

Thanks for your interest in contributing!

## Quick Start

1. **Fork** the repo and create your branch:
   ```bash
   git checkout -b feature/my-change

2. **Make changes and commit**
    ```bash
    git add -A
    git commit -m "feat: briefly describe your change"
    ```

3. **Push and open a Pull Request (PR) to main**


  - Keep PRs focused and small when possible.
  - Write clear commit messages (e.g., feat:, fix:, docs:, chore:).
  - Update documentation if behavior changes.
  - Ensure Docker builds and basic runtime paths are not broken.

## Building the image

We prefer that out `docker_build.sh` script is used. Our intention is to give users a simple, OS-independent tool without typing exhausting commands.
If for some reason you need to build manually, also try to embed your options into the build script. 

## Reporting Issues

Use GitHub Issues and include:

- What you did (commands, config),
- What you expected,
- What happened (logs, errors, versions).

## Code Style
- Python code should follow [PEP8](https://peps.python.org/pep-0008/) as much as possible.
- Use 4 spaces for indentation (no tabs).
- Prefer descriptive variable and function names.
- Document functions with short docstrings or simple comments. Please avoid using long docsstring blocks.