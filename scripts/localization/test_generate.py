import json
import tempfile
import unittest
from pathlib import Path

from generate import CATALOG, OUTPUTS, generate, load_catalog, render


class LocalizationTests(unittest.TestCase):
    def catalog(self, strings):
        return {"locale": "en-US", "strings": strings}

    def test_one_edit_reaches_both_platforms_with_overrides_and_platform_only_text(self):
        catalog = self.catalog({
            "addPhotos": "Import Photos",
            "reveal": {"text": "Show in Finder", "overrides": {"windows": "Show in Explorer"}},
            "windowsOnly": {"text": "Windows build", "platforms": ["windows"]},
        })
        outputs = render(catalog)
        windows = json.loads(outputs["windows"])
        self.assertIn('"addPhotos" = "Import Photos";', outputs["macos"])
        self.assertEqual("Import Photos", windows["addPhotos"])
        self.assertIn('"reveal" = "Show in Finder";', outputs["macos"])
        self.assertEqual("Show in Explorer", windows["reveal"])
        self.assertNotIn("windowsOnly", outputs["macos"])
        self.assertEqual("Windows build", windows["windowsOnly"])

    def test_reordered_repeated_arguments_keep_their_types_and_call_order(self):
        catalog = self.catalog({"progress": {
            "text": "{total} for {name}; {total} again (95%, {{literal}})",
            "arguments": [{"name": "name", "type": "string"}, {"name": "total", "type": "integer"}],
        }})
        output = render(catalog)
        self.assertIn('%2$ld for %1$@; %2$ld again (95%%, {literal})', output["macos"])
        windows = json.loads(output["windows"])["progress"]
        self.assertEqual("{1:N0} for {0}; {1:N0} again (95%, {{literal}})", windows)

    def test_native_escaping_preserves_quotes_newlines_backslashes_and_unicode(self):
        text = 'A "photo"\nC:\\Photos\t雪'
        output = render(self.catalog({"message": text}))
        self.assertEqual(text, json.loads(output["windows"])["message"])
        self.assertIn(r'"message" = "A \"photo\"\nC:\\Photos\t雪";', output["macos"])

    def test_invalid_placeholder_contracts_and_platforms_are_rejected(self):
        valid = {"text": "{count} photos", "arguments": [{"name": "count", "type": "integer"}]}
        invalid = [
            {**valid, "text": "{missing}"},
            {**valid, "text": "No placeholder"},
            {**valid, "text": "{count:N0}"},
            {**valid, "text": "{count!r}"},
            {**valid, "text": "{count"},
            {**valid, "arguments": [{"name": "count", "type": "float"}]},
            {**valid, "arguments": valid["arguments"] * 2},
            {**valid, "overrides": {"windows": "Missing argument"}},
            {**valid, "overrides": {"linux": "{count}"}},
            {**valid, "platforms": ["windows", "windows"]},
            {**valid, "platforms": []},
        ]
        for entry in invalid:
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                render(self.catalog({"message": entry}))

    def test_check_detects_missing_or_edited_outputs_without_rewriting_them(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / CATALOG
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps(self.catalog({"label": "First"})), encoding="utf-8")
            self.assertEqual(list(OUTPUTS.values()), generate(root, check=True))
            generate(root)
            self.assertEqual([], generate(root, check=True))
            windows = root / OUTPUTS["windows"]
            windows.write_bytes(windows.read_bytes().replace(b"\n", b"\r\n"))
            self.assertEqual([], generate(root, check=True))
            windows.write_text("hand edit", encoding="utf-8")
            self.assertEqual([OUTPUTS["windows"]], generate(root, check=True))
            self.assertEqual("hand edit", windows.read_text())
            source.write_text(json.dumps(self.catalog({"label": "Updated"})), encoding="utf-8")
            self.assertEqual(list(OUTPUTS.values()), generate(root, check=True))
            generate(root)
            self.assertEqual("Updated", json.loads(windows.read_text())["label"])

    def test_duplicate_json_keys_are_not_silently_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "catalog.json"
            path.write_text('{"locale":"en-US","strings":{"label":"First","label":"Second"}}')
            with self.assertRaisesRegex(ValueError, "Duplicate catalog field: label"):
                load_catalog(path)


if __name__ == "__main__":
    unittest.main()
