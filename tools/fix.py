import argparse
from pathlib import Path


def process_ovpn_files(config_dir: Path, pass_file_path: str) -> None:
    ovpn_files = sorted(config_dir.glob("*.ovpn"))

    if not ovpn_files:
        print(f"No .ovpn files found in {config_dir}")
        return

    for filepath in ovpn_files:
        print(f"Processing: {filepath.name}")
        lines = filepath.read_text(encoding="utf-8").splitlines(keepends=True)

        new_lines = []
        modified = False
        found_auth_line = False

        for line in lines:
            if line.strip().startswith("auth-user-pass"):
                new_lines.append(f"auth-user-pass {pass_file_path}\n")
                modified = True
                found_auth_line = True
            else:
                new_lines.append(line)

        if not found_auth_line:
            if new_lines and not new_lines[-1].endswith("\n"):
                new_lines[-1] = f"{new_lines[-1]}\n"
            new_lines.append(f"auth-user-pass {pass_file_path}\n")
            modified = True

        if modified:
            filepath.write_text("".join(new_lines), encoding="utf-8")
            print("  -> Updated successfully.")


if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    parser = argparse.ArgumentParser(description="Update auth-user-pass path in .ovpn files")
    parser.add_argument("--config-dir", default=str(repo_root / "configs" / "ovpn"), help="Directory containing .ovpn files")
    parser.add_argument("--pass-path", default=str(repo_root / "pass.txt"), help="Path to pass.txt to write into auth-user-pass")
    args = parser.parse_args()

    process_ovpn_files(Path(args.config_dir), args.pass_path)
    print("\nAll done!")