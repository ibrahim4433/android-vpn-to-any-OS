import os
import re
import shutil
from datetime import datetime

# Define paths
INPUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'input'))
CONFIGS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'configs'))
DEFAULT_TXT = os.path.join(INPUT_DIR, 'default.txt')
AUTH_TXT = os.path.join(INPUT_DIR, 'auth.txt')

def main():
    # Ensure configs directory exists
    os.makedirs(CONFIGS_DIR, exist_ok=True)

    # Read default.txt
    with open(DEFAULT_TXT, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract connection blocks
    connection_pattern = re.compile(r'<connection>(.*?)</connection>', re.DOTALL)
    connection_blocks = connection_pattern.findall(content)

    connections = []
    for block in connection_blocks:
        # Extract remote IP and PORT
        remote_match = re.search(r'remote\s+([^\s]+)\s+(\d+)', block)
        if not remote_match:
            continue

        ip, port = remote_match.groups()

        # Extract protocol
        proto_match = re.search(r'proto\s+([a-zA-Z0-9]+)', block)
        proto = proto_match.group(1) if proto_match else 'udp'

        connections.append({
            'ip': ip,
            'port': port,
            'proto': proto
        })

    # Clean the template
    # Remove all <connection> blocks
    clean_template = connection_pattern.sub('', content)

    # Replace auth-user-pass line
    clean_template = re.sub(r'auth-user-pass\s+".*?"', 'auth-user-pass auth.txt', clean_template)

    # Remove management lines
    clean_template = re.sub(r'^management\s+.*$\n?', '', clean_template, flags=re.MULTILINE)
    clean_template = re.sub(r'^management-hold$\n?', '', clean_template, flags=re.MULTILINE)

    # Remove deprecated options
    clean_template = re.sub(r'^persist-key$\n?', '', clean_template, flags=re.MULTILINE)
    clean_template = re.sub(r'^fast-io$\n?', '', clean_template, flags=re.MULTILINE)

    # Ensure empty lines left by removed blocks are cleaned up slightly (optional but makes it cleaner)
    clean_template = re.sub(r'\n{3,}', '\n\n', clean_template)

    # Append redirect-gateway def1
    clean_template = clean_template.rstrip() + '\nredirect-gateway def1\n'

    # Create timestamped directory
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    output_dir_name = f'ovpn-{timestamp}'
    output_dir = os.path.join(CONFIGS_DIR, output_dir_name)
    os.makedirs(output_dir, exist_ok=True)

    # Copy auth.txt
    if os.path.exists(AUTH_TXT):
        shutil.copy(AUTH_TXT, os.path.join(output_dir, 'auth.txt'))
    else:
        print(f"Warning: {AUTH_TXT} not found.")

    # Generate ZZZ<N>.ovpn files
    for i, conn in enumerate(connections, start=1):
        # Inject proto and remote lines after 'dev tun'
        inject_str = f"proto {conn['proto']}\nremote {conn['ip']} {conn['port']}"

        # We need to insert it right after the line containing 'dev tun'
        def repl(match):
            return f"{match.group(0)}\n{inject_str}"

        final_config = re.sub(r'^dev tun.*$', repl, clean_template, count=1, flags=re.MULTILINE)

        # Save to file
        output_file = os.path.join(output_dir, f'ZZZ{i}.ovpn')
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(final_config)

    print(f"Successfully generated {len(connections)} .ovpn files in {output_dir}")

if __name__ == '__main__':
    main()
