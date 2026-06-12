import os
import re
import shutil
from datetime import datetime


CONNECTION_BLOCK_RE = re.compile(r"<connection>\s*(.*?)\s*</connection>", re.DOTALL | re.IGNORECASE)
REMOTE_RE = re.compile(r"^\s*remote\s+(\S+)\s+(\d+)\s*$", re.IGNORECASE | re.MULTILINE)
PROTO_RE = re.compile(r"^\s*proto\s+(\S+)\s*$", re.IGNORECASE | re.MULTILINE)
AUTH_USER_PASS_RE = re.compile(r"^\s*auth-user-pass(?:\s+.*)?$", re.IGNORECASE | re.MULTILINE)
MANAGEMENT_RE = re.compile(r"^\s*management(?:-hold)?\b.*$", re.IGNORECASE | re.MULTILINE)


def extract_connections(default_content: str):
    """Extract remote endpoint details from <connection> blocks."""
    connections = []
    for block_match in CONNECTION_BLOCK_RE.finditer(default_content):
        block = block_match.group(1)
        remote_match = REMOTE_RE.search(block)
        if not remote_match:
            continue
        ip, port = remote_match.group(1), remote_match.group(2)
        proto_match = PROTO_RE.search(block)
        proto = proto_match.group(1) if proto_match else None
        connections.append({"ip": ip, "port": port, "proto": proto})
    return connections


def clean_template(default_content: str) -> str:
    """Build a base template without connection blocks or Android-only directives."""
    template = CONNECTION_BLOCK_RE.sub("", default_content)
    template = AUTH_USER_PASS_RE.sub("auth-user-pass pass.txt", template)
    template = MANAGEMENT_RE.sub("", template)
    template = re.sub(r"\n{3,}", "\n\n", template).strip()

    if "redirect-gateway def1" not in template:
        template += "\nredirect-gateway def1"

    return template + "\n"


def inject_connection(template: str, connection: dict) -> str:
    """Insert protocol/remote directives for a single generated profile."""
    insert_lines = []
    if connection.get("proto"):
        insert_lines.append(f"proto {connection['proto']}")
    insert_lines.append(f"remote {connection['ip']} {connection['port']}")
    block = "\n".join(insert_lines) + "\n"

    dev_tun_match = re.search(r"^dev\s+tun\s*$", template, re.IGNORECASE | re.MULTILINE)
    if dev_tun_match:
        return template[: dev_tun_match.end()] + "\n" + block + template[dev_tun_match.end() :]
    return block + template


def main() -> None:
    """Generate timestamped OpenVPN profiles and copy pass.txt into output."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    default_path = os.path.join(repo_root, "input", "default.txt")
    pass_path = os.path.join(repo_root, "input", "pass.txt")
    configs_root = os.path.join(repo_root, "configs")

    if not os.path.exists(default_path):
        raise FileNotFoundError(f"Missing default file: {default_path}")
    if not os.path.exists(pass_path):
        raise FileNotFoundError(f"Missing pass file: {pass_path}")

    with open(default_path, "r", encoding="utf-8") as f:
        default_content = f.read()

    connections = extract_connections(default_content)
    if not connections:
        raise ValueError("No valid <connection> blocks with remote lines found in input/default.txt")

    template = clean_template(default_content)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_dir = os.path.join(configs_root, f"ovpn-{timestamp}")
    try:
        os.makedirs(output_dir, exist_ok=False)
    except FileExistsError as exc:
        raise FileExistsError(
            f"Output directory already exists: {output_dir}. Wait one second and retry."
        ) from exc

    shutil.copy2(pass_path, os.path.join(output_dir, "pass.txt"))

    for index, connection in enumerate(connections, start=1):
        ovpn_content = inject_connection(template, connection)
        output_file = os.path.join(output_dir, f"ZZZ{index}.ovpn")
        with open(output_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(ovpn_content)

    print(f"Generated {len(connections)} files in: {output_dir}")


if __name__ == "__main__":
    main()
