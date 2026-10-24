import json
import struct
import tempfile
import unittest
from pathlib import Path

from package_manifest import CHECKSUMS, MANIFEST, REQUIRED, architecture, generate, verify


class PackageManifestTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        for name in REQUIRED:
            path = self.folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic component")
        pe = bytearray(134)
        pe[:2] = b"MZ"
        struct.pack_into("<I", pe, 60, 128)
        pe[128:132] = b"PE\0\0"
        struct.pack_into("<H", pe, 132, 0x8664)
        (self.folder / "BorderMuse.exe").write_bytes(pe)
        (self.folder / "BorderMuse.runtimeconfig.json").write_text(json.dumps({"runtimeOptions": {"includedFrameworks": [{"name": "Microsoft.NETCore.App", "version": "10.0.13"}]}}))

    def test_identifies_package_and_detects_tampered_runtime(self):
        metadata = generate(self.folder, "a" * 40)
        self.assertEqual("x64", metadata["architecture"])
        self.assertEqual("a" * 40, metadata["sourceCommit"])
        self.assertEqual(len(REQUIRED) + 1, verify(self.folder))
        (self.folder / "coreclr.dll").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "coreclr.dll"):
            verify(self.folder)

    def test_preserves_existing_metadata(self):
        (self.folder / MANIFEST).write_text("existing")
        with self.assertRaisesRegex(ValueError, "preserving"):
            generate(self.folder, "a" * 40)
        self.assertEqual("existing", (self.folder / MANIFEST).read_text())

    def test_missing_runtime_and_external_frameworks_are_rejected(self):
        (self.folder / "coreclr.dll").unlink()
        with self.assertRaisesRegex(ValueError, "coreclr.dll"):
            generate(self.folder, "a" * 40)
        (self.folder / "coreclr.dll").write_bytes(b"synthetic")
        (self.folder / "BorderMuse.runtimeconfig.json").write_text(json.dumps({"runtimeOptions": {"framework": {"name": "Microsoft.NETCore.App"}}}))
        with self.assertRaisesRegex(ValueError, "include its .NET"):
            generate(self.folder, "a" * 40)

    def test_invalid_executable_and_incomplete_checksums_are_rejected(self):
        (self.folder / "BorderMuse.exe").write_bytes(b"invalid")
        with self.assertRaises(ValueError):
            architecture(self.folder / "BorderMuse.exe")
        (self.folder / CHECKSUMS).write_text("")
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            verify(self.folder)


if __name__ == "__main__":
    unittest.main()
