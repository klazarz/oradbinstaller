# Oracle AI Database Free installer

Interactive installers for [Oracle AI Database Free](https://container-registry.oracle.com/ords/ocr/ba/database/free). They prefer Podman, fall back to Docker, create a persistent local database, and can install SQLcl natively.

## Install

macOS or Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/klazarz/oradbinstaller/main/install.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/klazarz/oradbinstaller/main/install.ps1 | iex
```

The Windows command must be run in PowerShell, not Command Prompt. Review the script before executing a remote installer if your security policy requires it:

```bash
curl -fsSL https://raw.githubusercontent.com/klazarz/oradbinstaller/main/install.sh
```

## What it does

1. Detects macOS, Linux, or Windows and selects Podman if available, otherwise Docker.
2. If neither runtime is installed, shows a Podman installation path and exits without installing anything.
3. Prompts for **quick** or **advanced** installation. Quick mode asks only for the administrative password. Advanced mode supplies defaults for the container name, listener port, named data volume, character set, archive logging, and force logging.
4. Pulls `container-registry.oracle.com/database/free:latest`, creates a persistent named volume, launches the database, and waits until it is ready.
5. Detects native SQLcl (`sql`). If it is missing, it offers to install it. SQLcl needs Java 17+; the installer does not install Java automatically.

Oracle AI Database Free uses the fixed services `FREE` and `FREEPDB1`. After a successful SQLcl check, the installer displays this password-safe command:

```bash
sql sys@//localhost:1521/FREEPDB1 as sysdba
```

SQLcl prompts for the password, rather than putting it in shell history.

## Prerequisites and notes

- Install and start Podman or Docker before running the installer. On macOS, Podman may also require `podman machine init` and `podman machine start`.
- The default `oracle-free-data` named volume preserves data when the container is stopped or recreated. Deleting that volume deletes the database data.
- The installer will not replace an existing container with the selected name.
- If Oracle Container Registry requires authentication or licence acceptance in your environment, accept it and run `podman login container-registry.oracle.com` (or `docker login ...`) before retrying.
- The container password is supplied to the container runtime at startup. Avoid sharing terminal history or process listings from the installation session.

## Operations and uninstall

With Podman (replace with `docker` if selected):

```bash
podman logs -f oracle-free
podman stop oracle-free
podman start oracle-free
podman rm oracle-free                 # removes the container, retains data
podman volume rm oracle-free-data     # permanently deletes database data
```

## Development checks

```bash
bash -n install.sh
bash tests/install.sh
pwsh -NoProfile -Command 'Invoke-Pester ./tests/install.Tests.ps1'
```
