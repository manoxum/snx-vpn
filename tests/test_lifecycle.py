import subprocess
import shutil
import unittest

from test_image_build import DockerFixture


class LifecycleTests(DockerFixture):
    def install_command_link(self):
        self.install_link.parent.mkdir(parents=True, exist_ok=True)
        self.install_link.symlink_to(self.project / "snx.sh")

    def snapshot_repository(self):
        return {
            str(path.relative_to(self.project)): path.read_bytes()
            for path in self.project.rglob("*") if path.is_file()
        }

    def test_install_and_aliases_always_rebuild_without_cache(self):
        (self.root / "image").touch()
        for command in ("install", "build", "rebuild", "reinstall"):
            with self.subTest(command=command):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_snx(command)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                build = next(call for call in calls if call["args"][0] == "build")
                self.assertIn("--no-cache", build["args"])
                self.assertEqual(build["cwd"], str(self.project))
                self.assertEqual(self.install_link.resolve(), self.project / "snx.sh")
                self.assertNotIn("run", [call["args"][0] for call in calls])

    def test_reinstall_recreates_existing_container_and_preserves_ports(self):
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        result, calls = self.run_snx("reinstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = [call["args"][0] for call in calls]
        self.assertLess(commands.index("build"), commands.index("rm"))
        self.assertLess(commands.index("rm"), commands.index("run"))
        run = next(call["args"] for call in calls if call["args"][0] == "run")
        ports = [run[i + 1] for i, arg in enumerate(run) if arg == "-p"]
        self.assertEqual(ports, ["8080:80/tcp", "2222:22/tcp"])

    def test_reinstall_preserves_actual_host_network(self):
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        self.env["TEST_NETWORK_MODE"] = "host"
        result, calls = self.run_snx("reinstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        run = next(call["args"] for call in calls if call["args"][0] == "run")
        self.assertEqual(run[run.index("--network") + 1], "host")
        self.assertNotIn("-p", run)

    def test_reinstall_preserves_container_when_port_bindings_cannot_be_read(self):
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        self.env["TEST_BIND_FAIL"] = "1"
        result, calls = self.run_snx("reinstall")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Container preserved", result.stdout)
        self.assertNotIn("rm", [call["args"][0] for call in calls])
        self.assertNotIn("run", [call["args"][0] for call in calls])

    def test_failed_reinstall_preserves_installation_and_container(self):
        self.install_command_link()
        self.env["TEST_BUILD_FAIL"] = "1"
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        before = self.snapshot_repository()
        result, calls = self.run_snx("reinstall")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.install_link.is_symlink())
        self.assertEqual(self.snapshot_repository(), before)
        self.assertNotIn("rm", [call["args"][0] for call in calls])
        self.assertNotIn("run", [call["args"][0] for call in calls])

    def test_install_sh_uses_the_same_installation_flow(self):
        with (self.project / ".env.local").open("a") as env_file:
            env_file.write('SNX_IMAGE="custom/snx:test"\n')
        result = subprocess.run(
            ["bash", str(self.project / "install.sh")],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = next(call["args"] for call in self.docker_calls() if call["args"][0] == "build")
        self.assertEqual(build[build.index("-t") + 1], "custom/snx:test")
        self.assertTrue(self.install_link.is_symlink())

    def test_uninstall_removes_resources_but_preserves_repository_and_envs(self):
        self.install_command_link()
        self.env["TEST_CONTAINER_EXISTS"] = "1"
        (self.root / "image").touch()
        (self.root / "stale-image").touch()
        (self.project / ".env").write_text("PRESERVE=yes\n")
        before = self.snapshot_repository()
        result, calls = self.run_snx("uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.install_link.is_symlink())
        self.assertFalse((self.root / "image").exists())
        self.assertFalse((self.root / "stale-image").exists())
        self.assertEqual(self.snapshot_repository(), before)
        args = [call["args"] for call in calls]
        self.assertIn(["rm", "-fv", "snx"], args)
        self.assertIn(["image", "rm", "snx"], args)
        self.assertIn(["image", "rm", "old-snx-image"], args)
        self.assertIn(
            ["image", "ls", "-aq", "--filter", "dangling=true", "--filter", "label=io.snx-vpn.image=snx"],
            args,
        )
        self.assertFalse(any("prune" in call for call in args))

    def test_uninstall_succeeds_when_already_uninstalled(self):
        result, calls = self.run_snx("uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("rm", [call["args"][0] for call in calls])

    def test_uninstall_preserves_link_when_docker_is_unavailable(self):
        self.install_command_link()
        self.env["TEST_DAEMON_FAIL"] = "1"
        result, calls = self.run_snx("uninstall")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.install_link.is_symlink())
        self.assertEqual([call["args"] for call in calls], [["info"]])

    def test_uninstall_preserves_link_when_image_removal_fails(self):
        self.install_command_link()
        (self.root / "image").touch()
        self.env["TEST_REMOVE_FAIL"] = "1"
        result, _ = self.run_snx("uninstall")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.install_link.is_symlink())

    def test_uninstall_preserves_unrelated_command(self):
        self.install_link.parent.mkdir(parents=True)
        unrelated = self.root / "unrelated.sh"
        unrelated.write_text("#!/bin/sh\n")
        self.install_link.symlink_to(unrelated)
        result, _ = self.run_snx("uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.install_link.resolve(), unrelated)

    def test_install_refuses_to_overwrite_an_unrelated_command(self):
        self.install_link.parent.mkdir(parents=True)
        self.install_link.write_text("preserve\n")
        result, calls = self.run_snx("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install_link.read_text(), "preserve\n")
        self.assertEqual(calls, [])

    def test_completion_install_is_repeatable_and_uninstall_restores_shell_settings(self):
        bashrc = self.home / ".bashrc"
        zshrc = self.home / ".zshrc"
        bashrc.write_text("export KEEP_BASH=yes\n")
        zshrc.write_text("export KEEP_ZSH=yes\n")
        for command in ("install", "reinstall"):
            result, _ = self.run_snx(command)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        completion_dir = self.home / ".local/share/snx/completions"
        self.assertTrue((completion_dir / "snx.bash").is_file())
        self.assertTrue((completion_dir / "_snx").is_file())
        self.assertEqual(bashrc.read_text().count("# >>> snx completion >>>"), 1)
        self.assertEqual(zshrc.read_text().count("# >>> snx completion >>>"), 1)
        result, _ = self.run_snx("uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(bashrc.read_text(), "export KEEP_BASH=yes\n")
        self.assertEqual(zshrc.read_text(), "export KEEP_ZSH=yes\n")
        self.assertFalse(completion_dir.exists())
        self.assertEqual(list(self.home.glob("*.snx.*")), [])

    def test_completion_handles_shell_config_without_final_newline(self):
        bashrc = self.home / ".bashrc"
        bashrc.write_text("export KEEP_BASH=yes")
        for command in ("install", "reinstall", "uninstall"):
            result, _ = self.run_snx(command)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(bashrc.read_text(), "export KEEP_BASH=yes\n")

    def test_bash_completion_suggests_commands_and_expose_modes(self):
        completion = self.project / "completions/snx.bash"
        for words, index, expected in (
            ("snx re", 1, {"rebuild", "reinstall", "reconnect", "restart"}),
            ("snx expose o", 2, {"on", "off"}),
            ("snx uninstall ''", 2, set()),
        ):
            with self.subTest(words=words):
                result = subprocess.run(
                    ["bash", "-c", 'source "$1"; COMP_WORDS=(' + words + '); '
                     f'COMP_CWORD={index}; _snx_completion; printf "%s\\n" "${{COMPREPLY[@]}}"',
                     "bash", str(completion)],
                    env=self.env, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(set(result.stdout.split()), expected)

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_zsh_installed_integration_registers_completion(self):
        result, _ = self.run_snx("install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run(
            ["zsh", "-f", "-c", 'source "$HOME/.zshrc"; print -r -- "${_comps[snx]}"'],
            env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "_snx")
