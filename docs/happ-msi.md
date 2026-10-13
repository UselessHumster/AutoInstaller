# Пробный MSI Happ x64

Пакет `Happ-4.5.2-x64-experimental.msi` собран из файлов официального
`setup-Happ.x64.exe` версии 4.5.2; исходников самого приложения в репозитории
happ-desktop нет. SHA256 официального EXE:
`9ceee216a85ae6130c422acc3fd6d785bf7d7326e87ee4ff5f9f77d9bf4bf25e`.

Это локальная перепаковка, не официальный MSI Happ. Пользователь подтвердил ручную установку и запуск MSI на ноутбуке.
Профиль Alkaloid использует MSI через `scripts/Install-HappMsi.cmd`, который
предварительно устанавливает VC++ runtime. Файлы на флешке называются
`installers/HappSetup.msi` и `installers/Happ-VC-runtime-x64.exe`.

Пакет содержит 1635 файлов приложения, службу `HappService` (LocalSystem,
автоматический запуск, остановка/удаление при uninstall), общие ярлыки
и обработчик `happ://`. Каталог установки: `C:\Program Files\Happ`.
Перед установкой нужен Microsoft Visual C++ 2015–2022 x64 runtime;
`Happ-VC-runtime-x64.exe` извлечён из официального установщика.

Пример для отдельной тестовой Windows-машины без действующей EXE-установки Happ:

```powershell
.\Happ-VC-runtime-x64.exe /install /quiet /norestart
msiexec.exe /i .\Happ-4.5.2-x64-experimental.msi /qn /norestart
```

Проверено: компиляция MSI, x64 в summary, таблицы ServiceInstall/ServiceControl,
распаковка MSI и совпадение SHA256 всех 1635 файлов с извлечённым payload.
Ручная установка и запуск приложения подтверждены пользователем.
Автоматическая установка обёрткой, Proxy/TUN, импорт подписки, повторная
установка, удаление и работа обычного пользователя требуют отдельной проверки.
Распаковщик Inno Setup 6.7 выдавал предупреждения о невозможности проверки
внутренних checksum; целостность исходного EXE проверена по digest GitHub.

Воспроизведение: извлечь официальный EXE innoextract с поддержкой 6.7
(проверен dscharrer/innoextract PR 210), затем сгенерировать WiX:

```bash
python3 scripts/Build-HappMsi.py /path/to/payload/app /path/to/Happ.wxs --version 4.5.2
wixl -a x64 -o /path/to/Happ.msi /path/to/Happ.wxs
```

WiX source использует пути относительно своего файла. Бинарные установщики,
распакованный payload и готовый MSI не входят в Git.
