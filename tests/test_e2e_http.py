"""Disposable HTTP end-to-end test of publication, upgrade and rollback."""
import functools
import http.server
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import threading
import unittest
from urllib.request import urlopen

SOURCE = Path(__file__).resolve().parents[1] / "scripts" / "release.py"
spec = importlib.util.spec_from_file_location("release_http_test", SOURCE)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class StaticReleaseSmoke(unittest.TestCase):
    def test_static_http_deploy_upgrade_and_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sample"
            (root / "releases").mkdir(parents=True)
            archive = Path(directory) / "site.tar.gz"
            handler = functools.partial(
                http.server.SimpleHTTPRequestHandler,
                directory=str(root / "current"),
            )
            with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                url = f"http://127.0.0.1:{server.server_port}/index.html"
                try:
                    for sha, data in [("1" * 40, b"version-one"), ("2" * 40, b"version-two")]:
                        with tarfile.open(archive, "w:gz") as tar:
                            item = tarfile.TarInfo("./index.html")
                            item.size = len(data)
                            tar.addfile(item, io.BytesIO(data))
                        release.publish(root, sha, archive)
                        with urlopen(url, timeout=5) as response:
                            self.assertEqual(response.status, 200)
                            self.assertEqual(response.read(), data)
                    self.assertEqual(release.rollback(root), "releases/" + "1" * 40)
                    with urlopen(url, timeout=5) as response:
                        self.assertEqual(response.read(), b"version-one")
                    events = (root / "deploy-events.jsonl").read_text()
                    self.assertEqual(events.count('"action": "deploy"'), 2)
                    self.assertEqual(events.count('"action": "rollback"'), 1)
                finally:
                    server.shutdown()
                    thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
