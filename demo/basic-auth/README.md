# Basic Authentication Demo

This demo demonstrates HTTP Basic Authentication using Envoy Gateway's SecurityPolicy.

## Configuration

The demo uses:
- A **shared Gateway** (`shared-gateway`) with an HTTP listener on port 80
- An **HTTPRoute** that routes traffic to the echo service
- A **SecurityPolicy** that applies basic authentication to the HTTPRoute
- A Kubernetes Secret (`basic-auth-secret`) containing htpasswd entries with SHA-encrypted passwords

**Important**: Envoy Gateway only supports SHA format (`{SHA}base64_hash`) for basic authentication.

## Resources

- `httproute.yaml`: Contains both the HTTPRoute and SecurityPolicy definitions

## Credentials

The demo uses these test credentials (created automatically by `setup.sh`):
- **Username**: `admin`, **Password**: `admin123`
- **Username**: `user`, **Password**: `user123`

## Running the Demo

```bash
# Run the demo
./demo.sh basic-auth
```

The demo will:
1. Ensure the shared gateway is deployed
2. Deploy the HTTPRoute and SecurityPolicy
3. Test three scenarios:
   - Request without authentication (should return 401)
   - Request with valid credentials (should return 200)
   - Request with invalid credentials (should return 401)

## Testing Manually

After running the demo, you can test manually:

```bash
# Get the gateway address
GATEWAY_ADDRESS=$(kubectl get gateway shared-gateway -n gateway-demos -o jsonpath='{.status.addresses[0].value}')

# Without credentials (should return 401)
curl -H "Host: auth.example.com" "http://${GATEWAY_ADDRESS}/"

# With valid credentials (should return 200)
curl -u admin:admin123 -H "Host: auth.example.com" "http://${GATEWAY_ADDRESS}/"

# With invalid credentials (should return 401)
curl -u wrong:password -H "Host: auth.example.com" "http://${GATEWAY_ADDRESS}/"
```

## Generating New Passwords

To generate new htpasswd entries for Envoy Gateway (SHA format):

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

## Expected Behavior

- Requests without authentication should return **401 Unauthorized**
- Requests with valid credentials should return **200 OK** with the service response
- Requests with invalid credentials should return **401 Unauthorized**

## Cleanup

```bash
# Clean up this demo
./demo.sh --cleanup basic-auth
```
