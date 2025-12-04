# TLS Demo

This demo demonstrates TLS/HTTPS termination using Gateway API with certificates managed by cert-manager.

## Configuration

The demo uses:
- A **ClusterIssuer** (self-signed for demo, Let's Encrypt example provided)
- A **Certificate** resource that cert-manager uses to generate TLS certificates
- A **Gateway** with an HTTPS listener that references the certificate Secret
- An **HTTPRoute** that routes HTTPS traffic to the backend service

## Certificate Management

Cert-manager automatically:
1. Watches for Certificate resources
2. Requests certificates from the configured Issuer
3. Creates a Kubernetes Secret with the certificate and private key
4. Renews certificates before expiration

## Self-Signed vs Let's Encrypt

### Self-Signed (Demo)
- **Pros**: Works immediately, no external dependencies, good for testing
- **Cons**: Browsers will show security warnings, not suitable for production
- **Use case**: Development, testing, internal services

### Let's Encrypt (Production)
- **Pros**: Free, trusted by browsers, automatic renewal
- **Cons**: Requires real domain name, DNS/HTTP validation
- **Use case**: Production environments with public domains

## Testing

```bash
# Test HTTPS endpoint (will show certificate warning for self-signed)
curl -k https://<gateway-address>/ -H "Host: tls.example.com"

# Test with verbose output to see certificate details
curl -k -v https://<gateway-address>/ -H "Host: tls.example.com"

# Test HTTP endpoint (should redirect or work independently)
curl http://<gateway-address>/ -H "Host: tls.example.com"
```

## Certificate Status

Check certificate status:
```bash
kubectl get certificate -n gateway-demos
kubectl describe certificate tls-cert -n gateway-demos
```

Check the Secret created by cert-manager:
```bash
kubectl get secret tls-cert -n gateway-demos
kubectl describe secret tls-cert -n gateway-demos
```

## Production Setup

For production with Let's Encrypt:

1. Update `issuer.yaml` to use the Let's Encrypt ClusterIssuer
2. Update `certificate.yaml` to reference the Let's Encrypt issuer
3. Ensure your domain DNS points to the Gateway's external IP
4. Cert-manager will automatically obtain and renew certificates

