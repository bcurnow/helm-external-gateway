# helm-external-gateway

A Helm chart that puts a [Gateway API](https://gateway-api.sigs.k8s.io/) front door on backends that
live **outside** the cluster: a NAS, a Home Assistant box, a Prometheus on a VM. It renders:

| Object | Purpose |
|---|---|
| `Service` + `EndpointSlice`s | A selector-less Service whose endpoints are the external IPs. IPv4 and IPv6 addresses are split into separate slices automatically, so IPv4-only, IPv6-only and dual-stack all work. |
| `Gateway` (+ optional `GatewayClass`) | Listeners for HTTP, HTTPS, TLS (terminate or passthrough), TCP, UDP. |
| `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `TCPRoute`, `UDPRoute` | Any number, any mix. |
| `Certificate` | cert-manager certificate for the listener. |
| `BackendTLSPolicy` | Re-encrypt to the backend and verify it against your own CA bundle or the system roots. |
| `ConfigMap`, `ReferenceGrant` | CA bundles for the policy above; cross-namespace grants. |

Each piece is optional. With `gateway.enabled=false` it is just a Service in front of external
endpoints (a `LoadBalancer` Service over a Ceph RGW, say).

## Install

```
helm install myapp oci://ghcr.io/bcurnow/charts/external-gateway --version 0.1.0 -f values.yaml
```

Requires Gateway API CRDs, a Gateway implementation, and (for `certificate`) cert-manager. The chart
installs none of these.

## Minimal example

```yaml
hostnames: [app.example.com]
gateway:
  gatewayClassName: cilium
  infrastructure:
    annotations:
      lbipam.cilium.io/ips: 192.0.2.10,2001:db8::10   # implementation-specific, passed through as-is
certificate:
  enabled: true
  issuerRef: {group: cert-manager.io, kind: ClusterIssuer, name: letsencrypt}
service:
  ports:
    - {name: https, port: 443, targetPort: 8443, appProtocol: https}
  endpoints:
    - hostname: backend1
      addresses: [192.0.2.20, "2001:db8::20"]
  backendTLS:
    enabled: true
    validation:
      hostname: backend.example.com
      wellKnownCACertificates: System
```

That renders an HTTPS listener for `app.example.com` using the certificate's secret, an `HTTPRoute`
sending `/` to the Service, a Service with an IPv4 and an IPv6 EndpointSlice, and a BackendTLSPolicy.
More cases are in [`charts/external-gateway/ci/`](charts/external-gateway/ci): IPv4-only HTTP,
IPv6-only HTTPS, TLS passthrough, TCP and UDP, a LoadBalancer Service with no Gateway, ExternalName,
and a kitchen-sink that sets metadata on every object.

## How values map to objects

Every object follows one rule: a few **reserved keys** are chart controls, and **every other key is
copied verbatim into the object's `spec`**. So any field the CRD defines works, including ones added
in future Gateway API releases, with no chart change.

| Values key | Object | Reserved keys (everything else is spec) |
|---|---|---|
| `gatewayClass` | GatewayClass | `enabled name labels annotations` |
| `gateway` | Gateway | `enabled name namespace labels annotations defaultListener` |
| `route`, `extraRoutes[]` | `kind`-dependent Route | `enabled kind apiVersion name namespace labels annotations` |
| `service`, `extraServices[]` | Service (+ slices, policy) | `enabled name namespace labels annotations ports endpoints endpointSlice backendTLS` |
| `service.backendTLS` | BackendTLSPolicy | `enabled name labels annotations` |
| `certificate`, `extraCertificates[]` | Certificate | `enabled name namespace labels annotations` |
| `caConfigMaps[]` | ConfigMap | `name namespace labels annotations` (rest is `data`, `binaryData`, `immutable`) |
| `referenceGrants[]` | ReferenceGrant | `name namespace labels annotations` |

`labels` and `annotations` are available on every object, merged over `commonLabels` and
`commonAnnotations`. `apiVersions` overrides the apiVersion per kind, for older or experimental
Gateway API installs.

### Defaults, so the common case is short

- **Listeners:** with no `gateway.listeners`, one is generated per entry in `hostnames` from
  `gateway.defaultListener` (protocol, port, TLS secret, `tls`, `allowedRoutes`). Set `listeners`
  yourself for anything else.
- **Routes:** hostnames come from `hostnames`, `parentRefs` point at this release's Gateway, and with
  no `rules` everything goes to the primary Service. In your own `rules`, a `backendRef` that omits
  `name` (and `port`) is filled with the primary Service, so `backendRefs: [{weight: 90}]` works.
- **Certificates:** `dnsNames` defaults to `hostnames`, `secretName` to `<first name>-tls`.
- **EndpointSlices:** named `<service>-<port>` and `<service>-<port>-v6`; `conditions` defaults to
  `{ready: true}`. The numeric slice port comes from `endpointPort`, else `targetPort`, else `port`.
  Set `endpointPort` when `targetPort` is a name.
- **Naming:** the primary Service, Gateway and `<name>-default-route` take the release name. Set
  `fullnameOverride`, or any object's `name`, to adopt existing objects without renaming them.

### Notes

- TCPRoute and UDPRoute are experimental-channel Gateway API; they default to `v1alpha2`. TLSRoute and
  BackendTLSPolicy are `v1` in recent Gateway API; use `apiVersions` on older installs.
- EndpointSlices with `addressType: FQDN` are not generated. Use `service.type: ExternalName`.
- Values are validated by `values.schema.json`; native fields (`listeners`, `rules`, ...) are
  deliberately left open.

## Development

```
helm lint charts/external-gateway -f charts/external-gateway/ci/kitchen-sink-values.yaml
helm template t charts/external-gateway -f charts/external-gateway/ci/dual-stack-https-values.yaml
```

CI lints and renders every `ci/*-values.yaml` fixture and validates the output with kubeconform
against the Gateway API and cert-manager schemas. Pushing a tag `vX.Y.Z` that matches `Chart.yaml`
publishes the chart to `oci://ghcr.io/<owner>/charts`.

## License

Apache-2.0
