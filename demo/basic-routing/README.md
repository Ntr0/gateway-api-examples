# Basic Routing Demo

This demo demonstrates basic HTTP routing using Gateway API, routing traffic from a Gateway to a single backend service.

## Configuration

The demo uses:
- A **shared Gateway** (`shared-gateway`) with an HTTP listener on port 80
- An **HTTPRoute** that matches all paths (`/`) and routes to the `echo-service` backend

## Resources

- `httproute.yaml`: Defines the routing rule that forwards all traffic to the echo service

## Running the Demo

```bash
# Run the demo
./demo.sh basic-routing
```

The demo will:
1. Ensure the shared gateway is deployed
2. Deploy the HTTPRoute
3. Make 5 test requests to verify routing works
4. Display the responses

## Testing Manually

After running the demo, you can test manually:

```bash
# Get the gateway address
GATEWAY_ADDRESS=$(kubectl get gateway shared-gateway -n gateway-demos -o jsonpath='{.status.addresses[0].value}')

# Make a request
curl -H "Host: example.com" "http://${GATEWAY_ADDRESS}/"
```

## Expected Behavior

- All requests to the gateway should be routed to the `echo-service`
- Responses should return "Hello from Gateway API - Echo Service!"
- HTTP status code should be 200

## Cleanup

```bash
# Clean up this demo
./demo.sh --cleanup basic-routing
```

