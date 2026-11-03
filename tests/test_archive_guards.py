import io
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "pd_security", Path(__file__).resolve().parents[1] / "scripts" / "release.py"
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


def package(path, members):
    with tarfile.open(path, "w:gz") as tar:
        for name, contents, kind in members:
            info = tarfile.TarInfo(name)
            if kind == "file":
                info.size = len(contents)
                tar.addfile(info, io.BytesIO(contents))
            elif kind == "dir":
                info.type = tarfile.DIRTYPE
                tar.addfile(info)
            elif kind == "hardlink":
                info.type = tarfile.LNKTYPE
                info.linkname = "/etc/passwd"
                tar.addfile(info)
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = "../../etc/passwd"
                tar.addfile(info)
            else:
                raise AssertionError(kind)


class ArchiveGuards(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name) / "sample"
        (self.root / "releases").mkdir(parents=True)
        self.archive = Path(tmp.name) / "site.tgz"

    def expect_blocked(self, members):
        package(self.archive, members)
        with self.assertRaises(ValueError):
            release.publish(self.root, "a" * 40, self.archive)
        self.assertFalse((self.root / "current").is_symlink())

    def test_reject_absolute(self):
        self.expect_blocked([("/etc/passwd", b"bad", "file")])

    def test_reject_traversal(self):
        self.expect_blocked([("./../../escape", b"bad", "file")])

    def test_reject_hardlink(self):
        self.expect_blocked([("danger", b"", "hardlink")])

    def test_reject_symlink(self):
        self.expect_blocked([("danger", b"", "symlink")])

    def test_reject_duplicate_files(self):
        self.expect_blocked([("a", b"1", "file"), ("a", b"2", "file")])

    def test_reject_max_unpacked_size(self):
        with patch.object(release, "MAX_BYTES", 3):
            self.expect_blocked([("test.txt", b"larger", "file")])

    def test_reject_member_count(self):
        with patch.object(release, "MAX_MEMBERS", 1):
            self.expect_blocked([("a", b"1", "file"), ("b", b"2", "file")])

    def test_reject_corrupted_archive_and_preserve_current(self):
        package(self.archive, [("index.html", b"before", "file")])
        release.publish(self.root, "b" * 40, self.archive)
        self.archive.write_bytes(b"not a tar archive")
        with self.assertRaises(tarfile.TarError):
            release.publish(self.root, "c" * 40, self.archive)
        self.assertEqual((self.root / "current" / "index.html").read_bytes(), b"before")

    def test_nested_static_files(self):
        package(self.archive, [
            ("assets", b"", "dir"),
            ("assets/app.css", b"body{}", "file"),
            ("index.html", b"ok", "file"),
        ])
        release.publish(self.root, "d" * 40, self.archive)
        self.assertEqual((self.root / "current" / "assets" / "app.css").read_bytes(), b"body{}")


if __name__ == "__main__":
    unittest.main()
