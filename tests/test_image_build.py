import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class DockerFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="snx tests ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        source = Path(__file__).resolve().parents[1]
        shutil.copy(source / "snx.sh", self.project / "snx.sh")
        shutil.copy(source / "install.sh", self.project / "install.sh")
        shutil.copy(source / "Dockerfile", self.project / "Dockerfile")
        shutil.copytree(source / "completions", self.project / "completions")
        (self.project / ".env.local").write_text(
            "SNX_IMAGE=snx\nSNX_NAME=snx\nSNX_SSH_BIND=2222\nHOST_EXPOSED=off\n"
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "snx").symlink_to(self.project / "snx.sh")
        self.log = self.root / "docker.jsonl"
        docker = self.bin / "docker"
        docker.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with open(os.environ["TEST_DOCKER_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "cwd": os.getcwd()}) + "\\n")
image = Path(os.environ["TEST_IMAGE_FILE"])
if args[:2] == ["image", "inspect"]:
    sys.exit(0 if image.exists() else 1)
elif args[0] == "build":
    if os.environ.get("TEST_BUILD_FAIL") == "1":
        sys.exit(1)
    image.touch()
elif args[0] == "info":
    sys.exit(1 if os.environ.get("TEST_DAEMON_FAIL") == "1" else 0)
elif args[:2] == ["image", "ls"]:
    stale = Path(os.environ["TEST_STALE_IMAGE_FILE"])
    if stale.exists():
        print("old-snx-image")
elif args[:2] == ["image", "rm"]:
    if os.environ.get("TEST_REMOVE_FAIL") == "1":
        sys.exit(1)
    target = Path(os.environ["TEST_STALE_IMAGE_FILE"]) if "old-snx-image" in args else image
    target.unlink(missing_ok=True)
elif args[0] == "ps":
    if os.environ.get("TEST_CONTAINER_EXISTS") == "1":
        print("snx")
elif args[0] == "inspect":
    print('{}' if "--format" in args else os.environ.get("TEST_NETWORK_MODE", "bridge"))
elif args[0] == "run" and not image.exists():
    print("pull access denied for snx, repository does not exist", file=sys.stderr)
    sys.exit(125)
''')
        docker.chmod(0o755)
        jq = self.bin / "jq"
        jq.write_text(
            '#!/bin/sh\ncat >/dev/null\n'
            'if [ "$TEST_BIND_FAIL" = "1" ]; then exit 1; fi\n'
            'printf "8080:80/tcp\\n2222:22/tcp\\n"\n'
        )
        jq.chmod(0o755)
        self.home = self.root / "home"
        self.home.mkdir()
        self.install_link = self.home / ".local" / "bin" / "snx"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_DOCKER_LOG": str(self.log),
            "TEST_IMAGE_FILE": str(self.root / "image"),
            "TEST_STALE_IMAGE_FILE": str(self.root / "stale-image"),
            "HOME": str(self.home),
            "TEST_BUILD_FAIL": "0",
            "TEST_CONTAINER_EXISTS": "0",
            "TEST_DAEMON_FAIL": "0",
            "TEST_REMOVE_FAIL": "0",
            "TEST_NETWORK_MODE": "bridge",
            "TEST_BIND_FAIL": "0",
        }

    def run_snx(self, command="connect"):
        result = subprocess.run(
            ["bash", str(self.bin / "snx"), command],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )
        calls = self.docker_calls()
        return result, calls

    def docker_calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]


class ImageBuildTests(DockerFixture):
    def test_missing_image_is_built_before_run(self):
        result, calls = self.run_snx()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = [call["args"][0] for call in calls]
        self.assertLess(commands.index("build"), commands.index("run"))
        build = next(call for call in calls if call["args"][0] == "build")
        self.assertEqual(build["args"], ["build", "--label", "io.snx-vpn.image=snx", "-t", "snx", "."])
        self.assertEqual(build["cwd"], str(self.project))

    def test_existing_image_is_reused(self):
        (self.root / "image").touch()
        result, calls = self.run_snx()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("build", [call["args"][0] for call in calls])
        self.assertIn(["image", "inspect", "snx"], [call["args"] for call in calls])

    def test_custom_image_name_is_used_for_build_and_run(self):
        with (self.project / ".env.local").open("a") as env_file:
            env_file.write("SNX_IMAGE=custom/snx:test\n")
        result, calls = self.run_snx()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            ["build", "--label", "io.snx-vpn.image=custom/snx:test", "-t", "custom/snx:test", "."],
            [c["args"] for c in calls],
        )
        run = next(call for call in calls if call["args"][0] == "run")
        self.assertEqual(run["args"][-1], "custom/snx:test")

    def test_failed_build_does_not_start_or_remove_container(self):
        self.env["TEST_BUILD_FAIL"] = "1"
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        result, calls = self.run_snx("reconnect")
        self.assertNotEqual(result.returncode, 0)
        commands = [call["args"][0] for call in calls]
        self.assertIn("build", commands)
        self.assertNotIn("run", commands)
        self.assertNotIn("rm", commands)


if __name__ == "__main__":
    unittest.main()
