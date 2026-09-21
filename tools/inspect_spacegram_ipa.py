"""Read IPA bundle, signed Mach-O entitlements and embedded profile (no signing)."""
import argparse
import io
import json
from pathlib import Path
import plistlib
import struct
import zipfile

ENTITLEMENTS = (
    "aps-environment", "application-identifier", "com.apple.developer.team-identifier",
    "keychain-access-groups", "com.apple.security.application-groups",
)


def signed_entitlements(data):
    # Read LC_CODE_SIGNATURE, then the XML entitlement slot in its superblob.
    # This is inspection, not cryptographic signature validation.
    magic = data[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack_from(">I", data, 4)[0]
        stride = 32 if magic[-1] == 0xbf else 20
        results = []
        for index in range(count):
            pos = 8 + index * stride
            fmt = ">QQ" if stride == 32 else ">II"
            offset, size = struct.unpack_from(fmt, data, pos + 8)
            results.extend(signed_entitlements(data[offset:offset + size]))
        return results
    formats = {b"\xcf\xfa\xed\xfe": ("<", 32), b"\xce\xfa\xed\xfe": ("<", 28),
               b"\xfe\xed\xfa\xcf": (">", 32), b"\xfe\xed\xfa\xce": (">", 28)}
    if magic not in formats:
        raise ValueError("Unsupported Mach-O header")
    endian, pos = formats[magic]
    count = struct.unpack_from(endian + "I", data, 16)[0]
    for _ in range(count):
        command, size = struct.unpack_from(endian + "II", data, pos)
        if size < 8 or pos + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x1d:
            offset, length = struct.unpack_from(endian + "II", data, pos + 8)
            blob = data[offset:offset + length]
            blob_magic, blob_length, slots = struct.unpack_from(">III", blob)
            if blob_magic != 0xfade0cc0 or blob_length > len(blob):
                raise ValueError("Invalid code signature superblob")
            for index in range(slots):
                _, slot_offset = struct.unpack_from(">II", blob, 12 + index * 8)
                slot_magic, slot_length = struct.unpack_from(">II", blob, slot_offset)
                if slot_offset + slot_length > len(blob):
                    raise ValueError("Invalid signature slot")
                if slot_magic == 0xfade7171:
                    return [plistlib.loads(blob[slot_offset + 8:slot_offset + slot_length])]
            return []
        pos += size
    return []


def profile_entitlements(data):
    start = data.find(b"<?xml")
    end = data.find(b"</plist>", start)
    if start < 0 or end < 0:
        raise ValueError("No XML plist in provisioning CMS envelope")
    return plistlib.loads(data[start:end + len(b"</plist>")])


def inspect(path):
    with zipfile.ZipFile(path) as outer:
        ipas = [n for n in outer.namelist() if n.lower().endswith(".ipa")]
        nested = io.BytesIO(outer.read(ipas[0])) if ipas else None
        with zipfile.ZipFile(nested or path) as archive:
            names = set(archive.namelist())
            bundles = []
            for name in sorted(names):
                if not name.startswith("Payload/") or not name.endswith("/Info.plist"):
                    continue
                parent = name.rsplit("/", 1)[0]
                if not (parent.endswith(".app") or parent.endswith(".appex")):
                    continue
                info = plistlib.loads(archive.read(name))
                executable = parent + "/" + info["CFBundleExecutable"]
                signed = signed_entitlements(archive.read(executable))
                profile_name = parent + "/embedded.mobileprovision"
                profile = profile_entitlements(archive.read(profile_name)) if profile_name in names else {}
                bundles.append({
                    "path": parent, "bundle_id": info.get("CFBundleIdentifier"),
                    "display_name": info.get("CFBundleDisplayName"),
                    "source_sha": info.get("SpaceGramSourceSHA"),
                    "extension_point": info.get("NSExtension", {}).get("NSExtensionPointIdentifier"),
                    "signed_entitlements": [{key: ent.get(key) for key in ENTITLEMENTS} for ent in signed],
                    "profile_entitlements": {key: profile.get("Entitlements", {}).get(key) for key in ENTITLEMENTS},
                    "profile_expiration": str(profile.get("ExpirationDate", "unavailable")),
                })
    return {"input": str(path), "signature_verification": "not performed; signed slots inspected", "bundles": bundles}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-notification-extension", action="store_true")
    args = parser.parse_args()
    result = inspect(args.ipa)
    encoded = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded)
    if args.require_notification_extension and not any(b["extension_point"] == "com.apple.usernotifications.service" for b in result["bundles"]):
        raise SystemExit("IPA lacks Notification Service Extension")


if __name__ == "__main__":
    main()
