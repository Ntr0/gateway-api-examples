# Rate Limiting Demo

This demo demonstrates rate limiting using Envoy Gateway's BackendTrafficPolicy, limiting requests to 5 per minute per client.

## Configuration

The demo uses:
- A **shared Gateway** (`shared-gateway`) with an HTTP listener on port 80
- An **HTTPRoute** that routes traffic to the echo service
- A **BackendTrafficPolicy** that applies rate limiting to the HTTPRoute:
  - Limit: 5 requests per minute
  - Unit: Minute
  - Type: Local (per-instance rate limiting)

## Resources

- `httproute.yaml`: Contains both the HTTPRoute and BackendTrafficPolicy definitions

## Rate Limiting Behavior

- **Allowed**: First 5 requests per minute return 200 OK
- **Rate Limited**: Subsequent requests return 429 Too Many Requests
- **Reset**: The limit resets after 1 minute

## Running the Demo

```bash
# Run the demo
./demo.sh rate-limiting
```

The demo will:
1. Ensure the shared gateway is deployed
2. Deploy the HTTPRoute and BackendTrafficPolicy
3. Make 10 rapid requests to demonstrate rate limiting
4. Display a summary showing successful vs rate-limited requests

## Testing Manually

After running the demo, you can test manually:

```bash
# Get the gateway address
GATEWAY_ADDRESS=$(kubectl get gateway shared-gateway -n gateway-demos -o jsonpath='{.status.addresses[0].value}')

# Make rapid requests to trigger rate limiting
for i in {1..10}; do
  curl -s -w "\nHTTP Status: %{http_code}\n" -H "Host: ratelimit.example.com" "http://${GATEWAY_ADDRESS}/"
  sleep 0.5
done
```

## Expected Behavior

- First 5 requests should return **200 OK**
- Requests 6-10 should return **429 Too Many Requests** (rate limited)
- After 1 minute, the limit resets and requests are allowed again

## Rate Limiting Configuration

The rate limit is configured in the BackendTrafficPolicy:

```yaml
rateLimit:
  local:
    rules:
    - limit:
        requests: 5
        unit: Minute
```

To modify the rate limit, edit `httproute.yaml` and update the `requests` and `unit` values.

## Cleanup

```bash
# Clean up this demo
./demo.sh --cleanup rate-limiting
```

