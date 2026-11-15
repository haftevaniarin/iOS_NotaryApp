#!/usr/bin/env python3
"""Check resolved staging target settings and compile APIConfig in both modes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
project = repo.parent / "test.xcodeproj"
env = dict(os.environ)
env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")


def run(args, **kwargs):
    return subprocess.run(args, env=env, text=True, capture_output=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="notaryledger-api-") as directory:
    scratch = Path(directory)
    main = scratch / "main.swift"
    main.write_text('import Foundation\nprint(APIConfig.environment.rawValue + " " + APIConfig.baseURL)\n')

    def compile_config(flags, optimize=False):
        return run(["xcrun", "swiftc", "-module-cache-path", str(scratch / "cache"),
                    "-O" if optimize else "-Onone", *sum((["-D", flag] for flag in flags), []),
                    str(repo / "APIConfig.swift"), str(main), "-o", str(scratch / "check")])

    for configuration in ["Debug", "Release"]:
        result = run(["xcodebuild", "-project", str(project), "-scheme", "NotaryLedger",
                      "-configuration", configuration, "-destination", "generic/platform=iOS",
                      "-showBuildSettings", "-json"])
        assert result.returncode == 0, result.stderr
        settings = next(item["buildSettings"] for item in json.loads(result.stdout)
                        if item["target"] == "NotaryLedger")
        assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "org.notaryledger.app.staging"
        flags = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
        assert {"STAGING", "STAGING_APP"}.issubset(flags), (configuration, flags)
        assert "PRODUCTION" not in flags, (configuration, flags)
        assert "-D" not in settings.get("OTHER_SWIFT_FLAGS", ""), "Inspect unexpected environment overrides"
        result = compile_config(flags, configuration == "Release")
        assert result.returncode == 0, result.stderr
        output = run([str(scratch / "check")], check=True).stdout.strip()
        assert output == "staging https://api-stage.notaryledger.org", output
        print(f"{configuration}: {output}")

    result = compile_config(["PRODUCTION"], True)
    assert result.returncode == 0, result.stderr
    assert run([str(scratch / "check")], check=True).stdout.strip() == "production https://notaryledger.org"
    print("Production: existing URL preserved")
    for flags in [["STAGING_APP"], ["STAGING_APP", "STAGING", "PRODUCTION"], ["STAGING_APP", "PRODUCTION"]]:
        result = compile_config(flags, True)
        assert result.returncode != 0 and "The staging app requires STAGING" in result.stderr, flags
    print("Invalid staging environment combinations: rejected by compiler")
