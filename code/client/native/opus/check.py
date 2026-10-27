"""Check built Opus libraries without enabling the optional extension in the game.

Each configuration runs in a temporary Godot project with only the native
extension and audio fixtures. No game assets, autoloads or editor cache are used.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


EXPECTED_CHECKS = (
    "decoder_class_registered", "decoder_instantiated", "test_data_read",
    "test_data_whole_frames", "decoded_frame_size", "decoded_level_matches",
    "decoded_audio_matches", "damaged_frame_refused", "damaged_frame_reported",
)


def run_godot(godot: Path, project: Path, *args: str) -> str:
    result = subprocess.run(
        [str(godot), "--headless", "--path", str(project), *args],
        capture_output=True, text=True, errors="replace", timeout=90,
    )
    output = result.stdout + result.stderr
    print(output, end="", flush=True)
    result.check_returncode()
    return output


def check(godot: Path, configuration: str) -> None:
    native = Path(__file__).resolve().parent
    tests = native.parents[1] / "tests"
    with tempfile.TemporaryDirectory(prefix="wanderville-opus-") as temporary:
        project = Path(temporary)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Opus decoder check"\n',
            encoding="utf-8",
        )
        extension = project / "native" / "opus"
        extension.mkdir(parents=True)
        shutil.copytree(native / "bin", extension / "bin")
        # The checked-in descriptor stays disabled so source-only game checkouts
        # can use PCM. Activate it only inside this disposable test project.
        descriptor = (native / "wanderville_opus.gdextension.off").read_text(
            encoding="utf-8"
        )
        if configuration == "release":
            # The editor binary normally chooses the debug library. Point that
            # feature entry at the release build to exercise both actual DLLs.
            descriptor = descriptor.replace("template_debug", "template_release")
        (extension / "wanderville_opus.gdextension").write_text(
            descriptor, encoding="utf-8"
        )
        (project / "tests").mkdir()
        shutil.copy2(tests / "opus_extension_check.gd", project / "tests")
        shutil.copytree(tests / "opus_data", project / "tests" / "opus_data")
        # Register the one known extension directly. This test has no imported
        # assets and does not need to start the editor to discover resources.
        (project / ".godot").mkdir()
        (project / ".godot" / "extension_list.cfg").write_text(
            "res://native/opus/wanderville_opus.gdextension\n", encoding="utf-8"
        )
        print(f"Checking Opus {configuration}", flush=True)
        output = run_godot(
            godot, project, "--script", "res://tests/opus_extension_check.gd"
        )
        missing = [name for name in EXPECTED_CHECKS
                   if f"OPUS_CHECK {name} PASS" not in output]
        if missing:
            raise RuntimeError(f"Decoder checks did not pass: {', '.join(missing)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--configuration", choices=("debug", "release", "both"),
                        default="both")
    args = parser.parse_args()
    godot = args.godot.resolve(strict=True)
    configurations = ("debug", "release") if args.configuration == "both" else (args.configuration,)
    for configuration in configurations:
        check(godot, configuration)


if __name__ == "__main__":
    main()
