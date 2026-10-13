"""Generate a WiX source for a locally extracted Happ x64 payload (wixl compiler)."""
import argparse
import hashlib
import os
from pathlib import Path
import uuid
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("payload", type=Path, help="innoextract app directory")
parser.add_argument("output", type=Path, help="output .wxs path")
parser.add_argument("--version", default="4.5.2")
args = parser.parse_args()
payload = args.payload.resolve()
for required in ("Happ.exe", "happd.exe", "Qt6Core.dll"):
    if not (payload / required).is_file():
        raise SystemExit(f"Missing payload: {required}")
ns = "http://schemas.microsoft.com/wix/2006/wi"
ET.register_namespace("", ns)
def element(parent, tag, **attrs):
    return ET.SubElement(parent, f"{{{ns}}}{tag}", attrs)
def stable_id(prefix, path):
    return prefix + hashlib.sha256(path.encode()).hexdigest()[:24]
wix = ET.Element(f"{{{ns}}}Wix")
product = element(wix, "Product", Id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"autoinstaller/happ/{args.version}")), Name="Happ (AutoInstaller MSI)", Language="1033", Version=args.version, Manufacturer="AutoInstaller repack", UpgradeCode="4AA33B60-32E2-48B3-992E-7BAE33658DB8")
element(product, "Package", InstallerVersion="500", Compressed="yes", InstallScope="perMachine")
element(product, "Media", Id="1", Cabinet="happ.cab", EmbedCab="yes")
element(product, "MajorUpgrade", DowngradeErrorMessage="A newer Happ MSI is already installed.")
prop = element(product, "Property", Id="VC_RUNTIME_INSTALLED")
element(prop, "RegistrySearch", Id="VCSearch", Root="HKLM", Key=r"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64", Name="Installed", Type="raw", Win64="yes")
condition = element(product, "Condition", Message="Install Microsoft Visual C++ 2015-2022 Redistributable (x64) before Happ.")
condition.text = "Installed OR VC_RUNTIME_INSTALLED"
rootdir = element(product, "Directory", Id="TARGETDIR", Name="SourceDir")
programfiles = element(rootdir, "Directory", Id="ProgramFiles64Folder")
install = element(programfiles, "Directory", Id="INSTALLFOLDER", Name="Happ")
menu = element(rootdir, "Directory", Id="ProgramMenuFolder")
menudir = element(menu, "Directory", Id="HAPPMENU", Name="Happ")
element(rootdir, "Directory", Id="DesktopFolder")
directories = {"": install}
components = []
for path in sorted(payload.rglob("*")):
    if not path.is_file():
        continue
    relative = path.relative_to(payload).as_posix()
    parent_parts = path.relative_to(payload).parent.parts
    current = ""
    for part in parent_parts:
        parent = current
        current = (current + "/" + part).strip("/")
        if current not in directories:
            directories[current] = element(directories[parent], "Directory", Id=stable_id("D", current), Name=part)
    cid = stable_id("C", relative)
    component = element(directories[current], "Component", Id=cid, Guid=str(uuid.uuid5(uuid.NAMESPACE_URL, "autoinstaller/happ/file/" + relative)), Win64="yes")
    components.append(cid)
    fid = stable_id("F", relative)
    file = element(component, "File", Id=fid, Name=path.name, Source=os.path.relpath(path, args.output.resolve().parent), KeyPath="yes")
    if relative == "Happ.exe":
        for directory, sid in (("HAPPMENU", "HappStartMenu"), ("DesktopFolder", "HappDesktop")):
            element(file, "Shortcut", Id=sid, Directory=directory, Name="Happ", WorkingDirectory="INSTALLFOLDER", Advertise="yes")
    if relative == "happd.exe":
        element(component, "ServiceInstall", Id="HappServiceInstall", Name="HappService", DisplayName="Happ Proxy Client Service", Description="Happ proxy and TUN background service", Type="ownProcess", Start="auto", Account="LocalSystem", ErrorControl="normal", Vital="yes")
        element(component, "ServiceControl", Id="HappServiceControl", Name="HappService", Start="install", Stop="both", Remove="uninstall", Wait="yes")
    if relative == "Happ.exe":
        element(component, "RegistryValue", Root="HKLM", Key=r"Software\Classes\happ", Type="string", Value="URL:Happ Protocol")
        element(component, "RegistryValue", Root="HKLM", Key=r"Software\Classes\happ", Name="URL Protocol", Type="string", Value="")
        element(component, "RegistryValue", Root="HKLM", Key=r"Software\Classes\happ\shell\open\command", Type="string", Value=f'"[#{fid}]" "%1"')
feature = element(product, "Feature", Id="Complete", Title="Happ", Level="1")
for cid in components:
    element(feature, "ComponentRef", Id=cid)
args.output.parent.mkdir(parents=True, exist_ok=True)
ET.indent(wix)
ET.ElementTree(wix).write(args.output, encoding="utf-8", xml_declaration=True)
print(f"WiX source generated: {len(components)} files")
