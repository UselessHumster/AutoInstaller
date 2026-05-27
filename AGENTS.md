# AGENTS.md

Guidance for agents working on this repository.

## Project Overview

This project is a portable Windows post-install automation tool.

The intended runtime is Windows PowerShell or PowerShell 7 on Windows, launched with administrator rights. The tool automates Windows workstation setup after first admin login: local software installation, computer rename, domain join, RDP, power policy, BitLocker, logging, and reusable company profiles.

## Repository Layout

- `Start-AutoInstaller.ps1` - main entrypoint.
- `modules/` - PowerShell modules.
- `profiles/` - company and department profiles.
- `installers/` - local `.msi` and `.exe` packages referenced by profiles.
- `config/` - shared defaults.
- `logs/` - generated run logs and reports.
- `scripts/Test-Project.ps1` - repository/profile validation helper.
- `docs/profile-schema.md` - profile format notes.

## Implementation Rules

- Keep the project portable. Do not require a central server, database, or cloud dependency for the core flow.
- Keep automation profile-driven. Company-specific values belong in `profiles/`, not hardcoded in modules.
- Do not store secrets in the repository. Passwords, domain credentials, VPN secrets, BitLocker recovery keys, and agent tokens must be entered interactively or supplied through a secure runtime mechanism.
- Do not write secrets to logs, CSV reports, error messages, or resume state.
- Prefer idempotent tasks. Re-running the tool should detect already completed work and avoid breaking the machine.
- Keep Windows-only operations behind runtime checks and support `-DryRun` for safe validation.
- Use local installer paths from profiles. Do not silently switch to internet package managers unless the product requirements change.
- Keep profiles compatible with `ConvertFrom-Yaml` and, where practical, JSON-compatible YAML for machines without YAML support.
- Preserve Windows PowerShell 5.1 compatibility unless a change explicitly raises the minimum version.

## PowerShell Style

- Use advanced functions with `[CmdletBinding()]` for public module functions.
- Keep `Set-StrictMode -Version Latest` in scripts/modules unless there is a specific compatibility reason not to.
- Use approved verbs where practical.
- Prefer explicit parameters over global variables.
- Return short status strings from task functions; the task runner owns status transitions and logging.
- Do not use aliases in scripts.

## Testing And Validation

Before handing off changes, run what is feasible for the current OS:

```powershell
.\scripts\Test-Project.ps1
```

On non-Windows machines, at minimum validate that JSON-compatible profiles parse:

```bash
ruby -rjson -e 'ARGV.each { |p| JSON.parse(File.read(p)); puts "json ok: #{p}" }' profiles/sample-company.yaml config/defaults.yaml
```

For Windows behavior, test at least:

- `-DryRun` CLI mode.
- UI launch.
- missing installer handling.
- repeated run after successful install detection.
- non-admin launch elevation.
- domain join only in a controlled test domain.

## Generated Files

- Do not commit generated logs under `logs/`.
- Do not commit local installer binaries unless the repository policy explicitly allows it.
- Keep `.gitkeep` files for empty runtime directories.
