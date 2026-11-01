#!/usr/bin/env bash
# Create a standalone application without requiring template dependencies.
set -euo pipefail

template_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$template_root" "$@" <<'PY'
import keyword
from pathlib import Path
import re
import shlex
import shutil
import sys


def main():
    if len(sys.argv) != 3:
        print("Usage: ./bin/init.sh /path/to/project", file=sys.stderr)
        return 2
    if sys.version_info < (3, 10):
        print("Python 3.10 or newer is required.", file=sys.stderr)
        return 2

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2]).expanduser().absolute()
    name = destination.name
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or keyword.iskeyword(name):
        print("The destination name must be a Python package name (for example, my_cli).", file=sys.stderr)
        return 2
    if name in {"tests", "rich", "dotenv"} or name in sys.stdlib_module_names:
        print(f"The package name {name!r} conflicts with a dependency or Python module.", file=sys.stderr)
        return 2
    if destination.exists() or destination.is_symlink():
        print(f"Destination already exists: {destination}. Choose a new directory.", file=sys.stderr)
        return 1
    if source == destination.resolve() or source in destination.resolve().parents:
        print("Choose a destination outside the template directory.", file=sys.stderr)
        return 2

    created = False
    try:
        destination.mkdir(parents=True, exist_ok=False)
        created = True
        # Copy only template sources; never inherit local credentials or artifacts.
        shutil.copytree(source / "project", destination / name,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.pyo"))
        (destination / "tests").mkdir()
        shutil.copy2(source / "tests/test_cli.py", destination / "tests/test_cli.py")
        for filename in (".gitignore", ".env.dist", "requirements.txt", "README.md", "AGENTS.md"):
            shutil.copy2(source / filename, destination / filename)

        for path in (destination / name).rglob("*.py"):
            path.write_text(path.read_text(encoding="utf-8").replace("python -m project", f"python -m {name}"), encoding="utf-8")
        test_path = destination / "tests/test_cli.py"
        test_path.write_text(re.sub(r"\bproject\b", name, test_path.read_text(encoding="utf-8")), encoding="utf-8")

        for filename in ("README.md", "AGENTS.md"):
            path = destination / filename
            text = path.read_text(encoding="utf-8")
            if filename == "README.md":
                start = text.index("## Create a new application")
                end = text.index("## Structure")
                text = text[:start] + """## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m project --help
python -m project --doctor
```

Edit `.env` to configure your application. On Windows, activate the virtual
environment with `.venv\\Scripts\\Activate.ps1` in PowerShell.
Initialize a Git repository with `git init` when ready.

""" + text[end:]
                text = text.replace("# Python CLI template", f"# {name}", 1)
            text = text.replace("python -m project", f"python -m {name}")
            text = text.replace("project/", f"{name}/").replace("from project.", f"from {name}.")
            path.write_text(text, encoding="utf-8")
        env_path = destination / ".env.dist"
        env_path.write_text(env_path.read_text(encoding="utf-8").replace("APP_NAME=project", f"APP_NAME={name}"), encoding="utf-8")
        shutil.copy2(env_path, destination / ".env")
    except OSError as exc:
        if created:
            shutil.rmtree(destination)
        print(f"Could not create project: {exc}", file=sys.stderr)
        return 1

    print(f"Created {name} at {destination}\n")
    print(f"cd {shlex.quote(str(destination))}")
    print("python3 -m venv .venv\nsource .venv/bin/activate")
    print("python -m pip install -r requirements.txt")
    print(f"python -m {name} --doctor")
    return 0


raise SystemExit(main())
PY
