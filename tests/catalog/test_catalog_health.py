"""Pruebas sin red de scripts/catalog_health.py: python3 -m unittest discover -s tests/catalog"""
import os, sys, unittest, urllib.error
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))
import catalog_health as ch

YAML = """PackageIdentifier: A.B
InstallerType: exe
Installers:
- Architecture: x64
  InstallerUrl: https://example.com/a-x64.exe
  InstallerSha256: %s
- Architecture: arm64
  InstallerUrl: https://example.com/a-arm.exe
  InstallerSha256: %s
- Architecture: x86
  InstallerUrl: ftp://example.com/skip.exe
  InstallerSha256: %s
""" % ("AB" * 32, "cd" * 32, "ef" * 32)


class Health(unittest.TestCase):
    def test_manifest_dir(self):
        self.assertEqual(ch.manifest_dir("OpenJS.NodeJS.LTS"), "o/OpenJS/NodeJS/LTS")

    def test_version_order(self):
        names = ["1.9", "1.10.2", "1.10", "2.0.0-rc1", "2.0.0"]
        self.assertEqual(sorted(names, key=ch.version_key, reverse=True)[0], "2.0.0")
        self.assertEqual(sorted(["1.9", "1.10"], key=ch.version_key)[-1], "1.10")

    def test_parse_installers(self):
        got = ch.parse_installers(YAML)
        self.assertEqual([i["arch"] for i in got], ["x64", "arm64"])
        self.assertEqual(got[0]["sha"], "ab" * 32)

    def test_catalog_urls(self):
        app = {"id": "x", "page": "https://p", "fallback": {"url": "https://f"}, "postInstall": {"link": "https://l"}, "desc": "https://no"}
        self.assertEqual([f for f, _ in ch.catalog_urls(app)], ["page", "fallback.url", "postInstall.link"])

    def test_classify(self):
        self.assertEqual(ch.classify_http(urllib.error.HTTPError("u", 404, "x", {}, None))[0], "error")
        self.assertEqual(ch.classify_http(urllib.error.HTTPError("u", 403, "x", {}, None))[0], "aviso")
        self.assertEqual(ch.classify_http(urllib.error.URLError("[Errno -2] Name or service not known"))[0], "error")

    def test_stale_hash_is_error_and_match_is_clean(self):
        ch.latest_version = lambda i: "1.0"
        class R:  # respuesta mínima del manifiesto
            def __init__(s, b): s.b = b
            def read(s): return s.b
            def __enter__(s): return s
            def __exit__(s, *a): return False
        ch.http = lambda *a, **k: R(YAML.encode())
        ch.sha256_of = lambda url: ("ab" * 32, 10) if "x64" in url else ("00" * 32, 10)
        out = ch.check_winget({"id": "ab", "winget": "A.B"})
        self.assertEqual([f[0] for f in out], ["error"])
        self.assertIn("HUELLA DESFASADA", out[0][2])


if __name__ == "__main__":
    unittest.main()
