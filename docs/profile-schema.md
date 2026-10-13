# Profile schema

Profiles describe one company and one or more departments. Keep secrets out of profiles.

The included sample is JSON-compatible YAML, so it works even when `ConvertFrom-Yaml` is unavailable.

## Top-level fields

- `company`: display name.
- `windows.enableRdp`: enables Remote Desktop and firewall rules.
- `windows.routes`: optional list of `{ "destinationPrefix": "10.0.0.0/8", "nextHop": "10.50.6.20" }`. Ensures persistent and active routes before domain join; chooses the interface used to reach the gateway. Existing unrelated routes are preserved.
- `windows.power.acSleepTimeoutMinutes`: AC sleep timeout. Use `0` to disable sleep on AC power.
- `windows.bitLocker.enable`: enables BitLocker on the system drive.
- `windows.bitLocker.inventoryApi.enabled`: optional. Sends serial number and recovery key to an inventory API when enabled.
- `windows.bitLocker.inventoryApi.url`: inventory API endpoint, for example `https://invent.datacloud.msk.ru/api/bitlocker-keys`.
- `windows.bitLocker.inventoryApi.apiKey`: runtime API key placeholder sent only in the `X-API-Key` header. Keep real secrets out of committed profiles.
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
- `installer.type`: `msi`, `exe`, or `bat`. EXE and BAT installers run with their directory as the working directory. BAT files run through `cmd.exe /d /s /c`.
- `installer.path`: relative path from the profile file.
- `installer.arguments`: silent install arguments.
- `installer.copyToTemp`: optional boolean. When true, copy the installer to the system temp directory and run it from there.
- `installer.continueWhenDetected`: optional boolean. When true, the task can finish once detection succeeds even if the installer process is still running.
- `installer.timeoutSeconds`: optional maximum installer runtime. Use `0` or omit it to wait without a timeout.
- `installer.detectionTimeoutSeconds`: optional wait after a successful installer exit for installed-state detection; throws on timeout. Useful for asynchronous bootstrap installers.
- `installer.stopProcessesOnDetected`: optional process names to stop after successful detection, useful for installers that launch a first-run UI.
- `detection.type`: `file`, `registry`, `command`, or `service`.
- `detection.name`: Windows service name for `service` detection; checks presence, not running state.
- `detection.path` or `detection.command`: installed-state check.

Optional `windows.inputLanguage` contains `languageTag` (for example `en-US`) and
`inputMethodTip` (`0409:00000409` for US keyboard). It sets the current user's first
language and default input method, preserving other languages. It does not change
existing domain users or the default profile of future users.

Optional `windows.fileCopies` is an array of `source` directory and `destination`
directory pairs. Sources resolve relative to the profile; destination environment
variables are expanded. Files are copied recursively and replaced on repeated runs.
Keep corporate payloads locally; they are not required to be stored in Git.

The graphical launcher lists profile tasks with checkboxes before execution.
Changing the department rebuilds the list and checks all its tasks. Only checked
tasks run; domain credentials are requested by the selected domain join task.

`detection.type: uninstall` checks application `DisplayName` in the Windows
uninstall registry entries (HKLM and HKCU, native and WOW6432Node).
`detection.name` is a PowerShell wildcard pattern, for example `Happ*`.
