# Profile schema

Profiles describe one company and one or more departments. Keep secrets out of profiles.

The included sample is JSON-compatible YAML, so it works even when `ConvertFrom-Yaml` is unavailable.

## Top-level fields

- `company`: display name.
- `windows.enableRdp`: enables Remote Desktop and firewall rules.
- `windows.power.acSleepTimeoutMinutes`: AC sleep timeout. Use `0` to disable sleep on AC power.
- `windows.bitLocker.enable`: enables BitLocker on the system drive.
- `departments`: department-specific domain and software selection.
- `software`: installer catalog.

## Department fields

- `id`: stable identifier used by `-DepartmentId`.
- `displayName`: UI label.
- `domain.name`: AD domain FQDN.
- `domain.ouPath`: target OU DN.
- `software`: list of software ids from the catalog.

## Software fields

- `id`: stable package id.
- `name`: UI/report name.
- `installer.type`: `msi` or `exe`.
- `installer.path`: relative path from the profile file.
- `installer.arguments`: silent install arguments.
- `installer.copyToTemp`: optional boolean. When true, copy the installer to the system temp directory and run it from there.
- `installer.continueWhenDetected`: optional boolean. When true, the task can finish once detection succeeds even if the installer process is still running.
- `installer.timeoutSeconds`: optional maximum installer runtime. Use `0` or omit it to wait without a timeout.
- `installer.stopProcessesOnDetected`: optional process names to stop after successful detection, useful for installers that launch a first-run UI.
- `detection.type`: `file`, `registry`, or `command`.
- `detection.path` or `detection.command`: installed-state check.
