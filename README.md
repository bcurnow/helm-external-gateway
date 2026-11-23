# helm-external-gateway

A Helm chart that puts a [Gateway API](https://gateway-api.sigs.k8s.io/) front door on backends that
live **outside** the cluster: a NAS, a Home Assistant box, a Prometheus on a VM. It renders:

| Object | Purpose |
|---|---|
| `Service` + `EndpointSlice`s | A selector-less Service whose endpoints are the external IPs. IPv4 and IPv6 addresses are split into separate slices automatically, so IPv4-only, IPv6-only and dual-stack all work. |
| `Gateway` (+ optional `GatewayClass`) | Listeners for HTTP, HTTPS, TLS (terminate or passthrough), TCP, UDP. |
| `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `TCPRoute`, `UDPRoute` | Any number, any mix. |
| `Certificate` | Optional, for options the Gateway annotation cannot express (duration, key algorithm, secretTemplate). |
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
hostnames:
  - app.example.com
gateway:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
service:
  ports:
    - port: 8080
  endpoints:
    - addresses:
        - 192.0.2.20
```

That renders an HTTPS listener for `app.example.com` on a `cilium` Gateway, an `HTTPRoute` sending `/`
to a Service on port 8080, and an EndpointSlice with the backend address. The listener's TLS secret
is named `app.example.com-tls`. The `cert-manager.io/cluster-issuer` annotation makes cert-manager
issue that certificate: its [Gateway API support](https://cert-manager.io/docs/usage/gateway/) creates
a Certificate for every TLS listener of an annotated Gateway. That support has to be enabled in
cert-manager (`config.enableGatewayAPI: true` in its chart). The chart itself does not render a
Certificate unless you ask for one.

Other `gatewayClassName` values go in `gateway.gatewayClassName`. Dual-stack needs only more addresses:

```yaml
service:
  ipFamilyPolicy: PreferDualStack
  endpoints:
    - addresses:
        - 192.0.2.20
        - "2001:db8::20"
```

Re-encrypt to a backend that serves TLS with a private CA:

```yaml
service:
  ports:
    - port: 443
      appProtocol: https
  backendTLS:
    enabled: true
    validation:
      hostname: backend.example.com
      caCertificateRefs:
        - kind: ConfigMap
          name: my-ca
```

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
  `name` (and `port`) is filled with the primary Service, so a `backendRef` that only sets `weight` works.
- **TLS secrets:** a generated TLS listener references `<hostname>-tls`; set `gateway.defaultListener.secretName` to use one secret for all of them. An explicit `certificate` defaults `dnsNames` to `hostnames` and `secretName` to `<first name>-tls`, and generated listeners then use that secret.
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
