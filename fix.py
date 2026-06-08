import os

# --- CONFIGURATION ---
# The path you want to add
pass_file_path = "/home/user/Desktop/test/pass.txt"
# The folder containing your .ovpn files. 
# "." means the current folder where this script is located.
directory = "." 
# ---------------------

def process_ovpn_files():
    # Loop through all files in the directory
    for filename in os.listdir(directory):
        if filename.endswith(".ovpn"):
            filepath = os.path.join(directory, filename)
            print(f"Processing: {filename}")
            
            with open(filepath, 'r') as file:
                lines = file.readlines()

            new_lines = []
            modified = False

            for line in lines:
                # Check if the line starts with 'auth-user-pass'
                # We use strip() to ignore leading/trailing whitespace when checking
                if line.strip().startswith("auth-user-pass"):
                    # Create the new line exactly as requested
                    # 'auth-user-pass' + space + your path + newline
                    new_line = f"auth-user-pass {pass_file_path}\n"
                    new_lines.append(new_line)
                    modified = True
                else:
                    new_lines.append(line)

            # Only write back to the file if we actually changed something
            if modified:
                with open(filepath, 'w') as file:
                    file.writelines(new_lines)
                print(f"  -> Updated successfully.")
            else:
                print(f"  -> 'auth-user-pass' not found, skipped.")

if __name__ == "__main__":
    process_ovpn_files()
    print("\nAll done!")