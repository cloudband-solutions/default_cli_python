"""Integration coverage for creating standalone applications."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/init.sh"


class InitTests(unittest.TestCase):
    def run_init(self, *args):
        return subprocess.run([str(SCRIPT), *map(str, args)], cwd="/",
                              capture_output=True, text=True, check=False)

    def test_generated_projects_run_and_pass_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ("project", "my_cli"):
                with self.subTest(name=name):
                    destination = Path(directory) / "parent with spaces" / name
                    result = self.run_init(destination)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue((destination / name / "__main__.py").is_file())
                    self.assertEqual((destination / ".env").read_text(),
                                     (destination / ".env.dist").read_text())
                    self.assertIn(f"APP_NAME={name}", (destination / ".env").read_text())
                    self.assertIn(f"python -m {name}", (destination / "README.md").read_text())
                    for excluded in (".git", ".venv", "bin", "tests/test_init.py"):
                        self.assertFalse((destination / excluded).exists())
                    self.assertFalse(list(destination.rglob("__pycache__")))
                    for args in (("-m", name, "--help"), ("-m", name, "--doctor"),
                                 ("-m", "unittest", "discover", "-s", "tests", "-v")):
                        check = subprocess.run([sys.executable, *args], cwd=destination,
                                               capture_output=True, text=True, check=False)
                        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_existing_destination_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "my_cli"
            destination.mkdir()
            sentinel = destination / "keep.txt"
            sentinel.write_text("keep")
            result = self.run_init(destination)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(sentinel.read_text(), "keep")
            self.assertEqual(list(destination.iterdir()), [sentinel])

    def test_bad_arguments_and_names(self):
        self.assertEqual(self.run_init().returncode, 2)
        self.assertEqual(self.run_init("one", "two").returncode, 2)
        with tempfile.TemporaryDirectory() as directory:
            for name in ("my-cli", "123app", "class", "json", "rich", "tests"):
                destination = Path(directory) / name
                self.assertEqual(self.run_init(destination).returncode, 2)
                self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
