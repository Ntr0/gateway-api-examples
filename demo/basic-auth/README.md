# Basic Auth Demo

This demo demonstrates HTTP Basic Authentication using Envoy Gateway's SecurityPolicy.

## Configuration

The demo uses:
- A Kubernetes Secret containing an `.htpasswd` file with SHA-encrypted passwords (required format for Envoy Gateway)
- A SecurityPolicy that references the secret and applies to the HTTPRoute

## Credentials

- **Username**: `admin`, **Password**: `admin123`
- **Username**: `user`, **Password**: `user123`

## Generating New Passwords

**Important**: Envoy Gateway only supports SHA format (`{SHA}base64_hash`) for basic authentication.

To generate new htpasswd entries, use:

```bash
# Generate SHA1 hash and base64 encode it
password_hash=$(echo -n "your_password" | openssl dgst -sha1 -binary | openssl base64)
echo "username:{SHA}${password_hash}"
```

Example:
```bash
# For password "admin123"
admin_hash=$(echo -n "admin123" | openssl dgst -sha1 -binary | openssl base64)
echo "admin:{SHA}${admin_hash}"
```

The secret is automatically created by `setup.sh` with the correct format.

## Testing

```bash
# Without credentials (should return 401)
curl -H "Host: auth.example.com" http://<gateway-address>/

# With valid credentials (should return 200)
curl -u admin:admin123 -H "Host: auth.example.com" http://<gateway-address>/

# With invalid credentials (should return 401)
curl -u wrong:password -H "Host: auth.example.com" http://<gateway-address>/
```

