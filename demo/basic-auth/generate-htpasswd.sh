#!/bin/bash
# Generate htpasswd file for basic auth
# Uses Python to generate bcrypt hashes if htpasswd is not available

python3 << 'EOF'
import bcrypt
import sys

def generate_htpasswd(username, password):
    # Generate bcrypt hash
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return f"{username}:${hashed.decode('utf-8')}"

# Generate entries
admin_hash = generate_htpasswd('admin', 'admin123')
user_hash = generate_htpasswd('user', 'user123')

print(admin_hash)
print(user_hash)
EOF


