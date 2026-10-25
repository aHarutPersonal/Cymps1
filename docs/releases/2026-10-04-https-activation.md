# Prepared HTTPS activation

The existing repository already contains a reviewed IP-certificate deployment and renewal workflow in `cmpys/infra/https`. It can protect the existing API address without purchasing a domain. The owner subsequently authorized issuance and acceptance of the linked terms. Activation and external trust validation have now succeeded; the client can use the HTTPS endpoint.

Issuer: Let's Encrypt, operated by Internet Security Research Group (ISRG). The currently published subscriber agreement was checked on 4 October 2026: [version 1.8, 6 July 2026](https://letsencrypt.org/documents/LE-SA-v1.8-July-06-2026.pdf), linked from the [official legal repository](https://letsencrypt.org/repository/).

Prepared action, only after the owner's consent: invoke the existing `setup.sh enable` workflow on the current server, obtain the IP certificate, validate its identity/chain/expiry, activate nginx HTTPS and the renewal timer, verify the public readiness endpoint with normal certificate validation, then build the client against HTTPS. There is no domain purchase or new paid service. Existing HTTP compatibility remains until client migration is complete; credentials must use HTTPS in the new build. Check renewal dry run and explicitly report any remaining failure.

Required owner decision: “May I accept the linked Let's Encrypt Subscriber Agreement on your behalf and enable the prepared HTTPS certificate and automatic renewal for this project's API?”

Consent is required because this accepts a legally binding agreement and activates security configuration; repository setup explicitly requires owner authorization. The owner explicitly authorized this action in the coordinating conversation before execution. The prepared workflow accepted the reviewed terms, issued the certificate and enabled renewal.

## Activation evidence

- Public `https://54.158.122.215/ready` returned 200 with database and Redis healthy, using normal system trust and IP identity verification (no insecure bypass).
- API base: `https://54.158.122.215/api/v1`.
- Issuer: Let's Encrypt YE2; SAN contains the existing API IPv4. Certificate expires 11 October 2026, 05:44:44 UTC.
- nginx configuration/identity/expiry checks passed. A brief local connect attempt during reload retried successfully.
- Renewal timer is enabled and active; next check was scheduled for 4 October 2026 around 16:02 UTC. The certificate renewal dry run succeeded.
- Existing HTTP compatibility remains for installed builds, while the new client must use HTTPS. Retire insecure API access after migrating existing clients; do not describe the old HTTP build as secure. No domain was bought and no firewall rule was changed.

## Direct application-port protection

The initial Compose mapping published port 8000 on all host interfaces, although an external probe timed out (no claim that it was publicly reachable). It is now bound only to host loopback. nginx continues to reach it locally. The web process accepts forwarding metadata from that private host/project-network boundary, while nginx replaces public forwarding headers; recovery quotas now see the actual client address. Production Compose also forwards the optional recovery SMTP settings, all disabled by default. A focused deployment check suite passed 17 tests, and external HTTPS availability remained successful after the web-only activation.
