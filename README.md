# Windows AutoInstaller

Переносимый PowerShell-инструмент для первичной настройки Windows-компьютера после первого входа администратора.

Проект управляется профилями: компания, отдел, домен, настройки Windows и локальные установщики описываются в файлах профилей. Секреты вводятся во время запуска и не должны храниться в репозитории.

## Что Делает

- Настраивает электропитание Windows, например отключает сон при питании от розетки.
- Включает Remote Desktop и правила Windows Firewall для RDP.
- Переименовывает компьютер.
- Вводит компьютер в домен Active Directory и нужный OU.
- Устанавливает локальные `.msi` и `.exe` пакеты в тихом режиме.
- При необходимости включает BitLocker.
- Пишет логи запуска и итоговые CSV-отчёты.

## Структура Проекта

- `Start-AutoInstaller.ps1` - основная точка входа.
- `modules/` - PowerShell-модули для конфигов, логирования, контекста запуска, выполнения задач, Windows-настроек, установки ПО и UI.
- `profiles/` - переиспользуемые профили компаний и отделов.
- `installers/` - локальные установщики, на которые ссылаются профили.
- `config/` - общие настройки по умолчанию.
- `logs/` - сгенерированные логи и отчёты.
- `scripts/Test-Project.ps1` - вспомогательная проверка проекта.
- `docs/profile-schema.md` - описание формата профиля.
- `AGENTS.md` - инструкции для будущих агентов, работающих с репозиторием.

## Требования

- Windows 10/11 или Windows Server, используемый как рабочая станция.
- Windows PowerShell 5.1 или PowerShell 7.
- Права администратора для реального применения настроек.
- Локальные установщики, размещённые в `installers/`.
- Доменная учётная запись для ввода в домен, вводится интерактивно во время запуска.

## Первый Тестовый Запуск

Скопируй проект на тестовый Windows-компьютер, например:

```text
C:\Tools\AutoInstaller
```

Открой PowerShell от имени администратора:

```powershell
cd C:\Tools\AutoInstaller
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

Сначала запусти безопасную проверку без внесения изменений:

```powershell
.\Start-AutoInstaller.ps1 -NoUi -ProfilePath .\profiles\sample-company.yaml -DepartmentId office -ComputerName TEST-PC-001 -DryRun
```

Запуск с UI:

```powershell
.\Start-AutoInstaller.ps1 -ProfilePath .\profiles\sample-company.yaml
```

Запуск без UI:

```powershell
.\Start-AutoInstaller.ps1 -NoUi -ProfilePath .\profiles\sample-company.yaml -DepartmentId office -ComputerName TEST-PC-001
```

## Установщики

Бинарные установщики не коммитятся в Git. Их нужно положить в пути, указанные в выбранном профиле, например:

```text
installers\
  chrome\GoogleChromeStandaloneEnterprise64.msi
  7zip\7z.msi
  adobe-reader\AcroRdrDC.exe
  openvpn\OpenVPN.msi
```

Каждый пакет в профиле описывает:

- `installer.type`: `msi` или `exe`;
- `installer.path`: относительный путь от файла профиля;
- `installer.arguments`: аргументы тихой установки;
- `detection`: проверку, установлен ли продукт.

## Профили

Профили лежат в `profiles/`. Примерный профиль сделан как JSON-compatible YAML, чтобы его можно было прочитать даже там, где нет `ConvertFrom-Yaml`.

Рекомендуемый порядок:

1. Скопировать `profiles/sample-company.yaml`.
2. Переименовать копию под компанию или тестовый стенд.
3. Изменить `company`, `departments`, настройки домена, OU и списки ПО.
4. Не хранить в профиле пароли, токены, VPN-секреты и ключи восстановления.

Подробности по полям профиля есть в `docs/profile-schema.md`.

## Проверка

На Windows:

```powershell
.\scripts\Test-Project.ps1
```

На macOS/Linux, если PowerShell не установлен, можно проверить JSON-compatible примеры профилей:

```bash
ruby -rjson -e 'ARGV.each { |p| JSON.parse(File.read(p)); puts "json ok: #{p}" }' profiles/sample-company.yaml config/defaults.yaml
```

## Логи И Отчёты

Каждый запуск пишет данные в `logs/<timestamp>/`:

- `run.log` - лог выполнения задач.
- `report.csv` - итоговый отчёт по статусам задач.

Сгенерированные логи и отчёты игнорируются Git.

## Безопасность

- Перед реальными изменениями запускай `-DryRun`.
- Начинай тест с короткого списка ПО, например Chrome и 7-Zip.
- Переименование и ввод в домен сначала проверяй в тестовом OU.
- BitLocker включай только после того, как базовый сценарий уже проверен.
- Не коммить реальные установщики, локальные профили, сертификаты, `.ovpn`, `.rdp`, ключи, учётные данные, логи и отчёты.
