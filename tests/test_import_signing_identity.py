import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "import_signing_identity.sh"

CONFIG = """[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Brimline Code Signing
O = Test
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
"""


@unittest.skipUnless(sys.platform == "darwin", "needs the macOS security and codesign tools")
class ImportSigningIdentityTests(unittest.TestCase):
    """A self-signed identity, like Brimline's, imported by the script as the release workflow does.

    Regression of THA-1839: the identity was imported and found, but `codesign` said "no identity
    found" on the runner, because the keychain of the run was not in the search list of the user.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.keychain = self.tmp / "brimline-signing.keychain-db"
        self.addCleanup(self.cleanup)

    def cleanup(self):
        subprocess.run(["security", "delete-keychain", str(self.keychain)], capture_output=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_ok(self, *args, **kwargs):
        return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)

    def make_p12(self):
        (self.tmp / "o.cnf").write_text(CONFIG)
        key, cert, p12 = (self.tmp / n for n in ("k.pem", "c.pem", "t.p12"))
        # The openssl of macOS (LibreSSL) writes a .p12 that `security import` reads.
        self.run_ok("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key),
                    "-out", str(cert), "-days", "2", "-config", str(self.tmp / "o.cnf"))
        self.run_ok("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                    "-out", str(p12), "-passout", "pass:secret")
        return subprocess.run(["base64", "-i", str(p12)], check=True, capture_output=True, text=True).stdout

    def test_the_identity_signs_without_naming_its_keychain(self):
        github_env = self.tmp / "github_env"
        github_env.write_text("")
        env = dict(os.environ, P12=self.make_p12(), P12_PASSWORD="secret", RUNNER_TEMP=str(self.tmp),
                   GITHUB_ENV=str(github_env))
        self.run_ok(str(SCRIPT), env=env)
        values = dict(line.split("=", 1) for line in github_env.read_text().splitlines())
        self.assertEqual(values["BRIMLINE_SIGNING_KEYCHAIN"], str(self.keychain))
        identity = values["BRIMLINE_SIGNING_IDENTITY"]
        self.assertRegex(identity, r"^[0-9A-F]{40}$")

        binary = self.tmp / "tool"
        shutil.copy("/bin/ls", binary)
        for extra in ([], ["--keychain", str(self.keychain)]):
            result = subprocess.run(["codesign", "--force", "-s", identity, *extra, str(binary)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.run_ok("codesign", "--verify", "--strict", str(binary))


if __name__ == "__main__":
    unittest.main()
