# Prepared HTTPS activation

The existing repository already contains a reviewed IP-certificate deployment and renewal workflow in `cmpys/infra/https`. It can protect the existing API address without purchasing a domain. The current public HTTPS handshake still fails; clients must not be changed to that endpoint until issuance and external trust validation succeed.

Issuer: Let's Encrypt, operated by Internet Security Research Group (ISRG). The currently published subscriber agreement was checked on 4 October 2026: [version 1.8, 6 July 2026](https://letsencrypt.org/documents/LE-SA-v1.8-July-06-2026.pdf), linked from the [official legal repository](https://letsencrypt.org/repository/).

Prepared action, only after the owner's consent: invoke the existing `setup.sh enable` workflow on the current server, obtain the IP certificate, validate its identity/chain/expiry, activate nginx HTTPS and the renewal timer, verify the public readiness endpoint with normal certificate validation, then build the client against HTTPS. There is no domain purchase or new paid service. Existing HTTP compatibility remains until client migration is complete; credentials must use HTTPS in the new build. Check renewal dry run and explicitly report any remaining failure.

Required owner decision: “May I accept the linked Let's Encrypt Subscriber Agreement on your behalf and enable the prepared HTTPS certificate and automatic renewal for this project's API?”

Consent is required because this accepts a legally binding agreement and activates security configuration; repository setup explicitly requires owner authorization. No terms have been accepted by this task. The pending decision does not block independent application fixes or local build verification.
