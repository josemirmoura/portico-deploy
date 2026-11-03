import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "release.py"
spec = importlib.util.spec_from_file_location("pd_release", MODULE)
pd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pd)


def archive(path, entries):
    with tarfile.open(path, "w:gz") as tf:
        for name, content, kind in entries:
            info = tarfile.TarInfo(name)
            if kind == "file":
                info.size = len(content)
                tf.addfile(info, io.BytesIO(content))
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = "../../etc/passwd"
                tf.addfile(info)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "testproject"
        (self.root / "releases").mkdir(parents=True)

    def test_deploy_and_rollback(self):
        sha1 = "a" * 40
        sha2 = "b" * 40
        for sha, data in [(sha1, b"first"), (sha2, b"second")]:
            pack = Path(self.temp.name) / (sha + ".tar.gz")
            archive(pack, [("index.html", data, "file")])
            pd.publish(self.root, sha, pack)
        self.assertEqual((self.root / "current" / "index.html").read_bytes(), b"second")
        pd.rollback(self.root)
        self.assertEqual((self.root / "current" / "index.html").read_bytes(), b"first")

    def test_first_release_can_rollback_to_empty(self):
        pack = Path(self.temp.name) / "first.tar.gz"
        archive(pack, [("index.html", b"candidate", "file")])
        pd.publish(self.root, "f" * 40, pack)
        self.assertTrue((self.root / "current").is_symlink())
        pd.rollback(self.root)
        self.assertFalse((self.root / "current").is_symlink())
        self.assertTrue((self.root / "releases" / ("f" * 40)).is_dir())

    def test_refuse_bad_active_symlink_before_new_release(self):
        (self.root / "current").symlink_to("../../etc")
        pack = Path(self.temp.name) / "safe.tar.gz"
        archive(pack, [("index.html", b"okay", "file")])
        with self.assertRaises(ValueError):
            pd.publish(self.root, "a" * 40, pack)
        self.assertFalse((self.root / "releases" / ("a" * 40)).exists())

    def test_forbid_traversal(self):
        pack = Path(self.temp.name) / "bad.tar.gz"
        archive(pack, [("../../escape", b"oops", "file")])
        with self.assertRaises(ValueError):
            pd.publish(self.root, "c" * 40, pack)
        self.assertFalse((Path(self.temp.name) / "escape").exists())

    def test_forbid_symlinks(self):
        pack = Path(self.temp.name) / "link.tar.gz"
        archive(pack, [("bad", b"", "symlink")])
        with self.assertRaises(ValueError):
            pd.publish(self.root, "d" * 40, pack)

    def test_forbid_replay(self):
        pack = Path(self.temp.name) / "ok.tar.gz"
        archive(pack, [("index.html", b"okay", "file")])
        pd.publish(self.root, "e" * 40, pack)
        with self.assertRaises(ValueError):
            pd.publish(self.root, "e" * 40, pack)

    def test_invalid_name(self):
        with self.assertRaises(ValueError):
            pd.validate_name("../foo", "a" * 40)


if __name__ == "__main__":
    unittest.main()
