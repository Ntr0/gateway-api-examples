# Advanced Routing Demo

This demo demonstrates weighted load balancing using Gateway API, distributing traffic between two backend services with an 80/20 split.

## Configuration

The demo uses:
- A **shared Gateway** (`shared-gateway`) with an HTTP listener on port 80
- An **HTTPRoute** that routes traffic to two backend services with different weights:
  - `echo-service-v1`: 80% of traffic (weight: 80)
  - `echo-service-v2`: 20% of traffic (weight: 20)
- Hostname-based routing using `weighted.example.com`

## Resources

- `httproute.yaml`: Defines weighted routing rules with hostname matching

## Running the Demo

```bash
# Run the demo
./demo.sh advanced-routing
```

The demo will:
1. Ensure the shared gateway is deployed
2. Deploy the HTTPRoute with weighted backend references
3. Make 20 test requests to observe traffic distribution
4. Display a summary showing the actual traffic split

## Testing Manually

After running the demo, you can test manually:

```bash
# Get the gateway address
GATEWAY_ADDRESS=$(kubectl get gateway shared-gateway -n gateway-demos -o jsonpath='{.status.addresses[0].value}')

# Make multiple requests to observe load balancing
for i in {1..20}; do
  curl -H "Host: weighted.example.com" "http://${GATEWAY_ADDRESS}/"
done
```

## Expected Behavior

- Approximately 80% of requests should be routed to `echo-service-v1` (returns "Service V1 - Weight: 80%")
- Approximately 20% of requests should be routed to `echo-service-v2` (returns "Service V2 - Weight: 20%")
- The actual distribution may vary slightly due to load balancing algorithms

## Traffic Distribution

The demo makes 20 requests and reports:
- Number of requests routed to V1 service
- Number of requests routed to V2 service
- Percentage distribution

## Cleanup

```bash
# Clean up this demo
./demo.sh --cleanup advanced-routing
```

