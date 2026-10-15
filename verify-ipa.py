"""Check this F50 build's bundle structure, architecture, encryption and signing."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import struct
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def macho_details(data, name):
    require(len(data) >= 32, f"Truncated executable: {name}")
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<8I", data)
    require(magic == 0xFEEDFACF, f"Expected a thin 64-bit Mach-O: {name}")
    require(cpu == 0x0100000C, f"Expected arm64: {name}")
    require(filetype in (2, 6), f"Unexpected Mach-O type: {name}")
    require(32 + sizeofcmds <= len(data), f"Invalid load-command area: {name}")
    platforms = []
    offset = 32
    for _ in range(ncmds):
        require(offset + 8 <= 32 + sizeofcmds, f"Truncated load command: {name}")
        command, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= 32 + sizeofcmds, f"Invalid load command: {name}")
        require(command != 0x1D, f"Unexpected code signature in unsigned output: {name}")
        if command in (0x21, 0x2C):
            require(size >= 20, f"Truncated encryption command: {name}")
            require(struct.unpack_from("<I", data, offset + 16)[0] == 0, f"Encrypted executable: {name}")
        if command == 0x32:
            require(size >= 24, f"Truncated build-version command: {name}")
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        elif command == 0x25:
            platforms.append(2)
        offset += size
    require(offset == 32 + sizeofcmds, f"Load-command size mismatch: {name}")
    require(platforms and all(platform == 2 for platform in platforms), f"Expected iPhoneOS, not simulator/macOS: {name}")
    return {"path": name, "architecture": "arm64", "platform": "iOS", "code_signature": False, "encrypted": False}


def verify(path):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "ZIP integrity check failed")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        for name in names:
            parts = pathlib.PurePosixPath(name).parts
            require(parts and parts[0] == "Payload" and ".." not in parts and "\\" not in name, f"Unexpected archive path: {name}")
            require("_CodeSignature" not in parts and not name.endswith("embedded.mobileprovision"), f"Unexpected signing material: {name}")

        main = "Payload/F50Monitor-iOS.app/"
        widget = main + "PlugIns/F50MonitorWidget.appex/"
        bundles = []
        for prefix, bundle_id in (
            (main, "com.kold.f50.monitor.ios"),
            (widget, "com.kold.f50.monitor.ios.widget"),
        ):
            info = plistlib.loads(archive.read(prefix + "Info.plist"))
            require(info.get("CFBundleIdentifier") == bundle_id, f"Unexpected bundle identifier: {prefix}")
            require(info.get("CFBundleShortVersionString") == "2.5", f"Unexpected app version: {prefix}")
            require(str(info.get("CFBundleVersion")) == "9", f"Unexpected build number: {prefix}")
            require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], f"Wrong bundle platform: {prefix}")
            require(info.get("MinimumOSVersion") == "16.0", f"Unexpected deployment target: {prefix}")
            binary = prefix + info["CFBundleExecutable"]
            require(binary in names, f"Missing executable: {binary}")
            bundles.append({"identifier": bundle_id, "version": "2.5", "build": "9", "minimum_ios": info["MinimumOSVersion"]})

        require(main + "Frameworks/F50Core.framework/F50Core" in names, "Missing embedded F50Core framework")
        binaries = []
        for name in names:
            if name.endswith("/"):
                continue
            with archive.open(name) as stream:
                magic = stream.read(4)
            if magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                binaries.append(macho_details(archive.read(name), name))
        require(len(binaries) >= 3, "Missing app, widget or framework executable")
    return {
        "file": path.name,
        "size_bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "status": "passed",
        "signing": "unsigned",
        "bundles": bundles,
        "executables": binaries,
        "real_device_installation_tested": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    args = parser.parse_args()
    report = verify(args.ipa)
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    args.report.write_text(text, encoding="utf-8")
    print(text)

