# Proposed production recovery email: Amazon SES

Recommend SES in `us-east-1`, already the project's AWS region, using the existing SMTP adapter with TLS on port 587. No new hosting provider is needed. This is a proposal, not an activated service.

## Read-only findings, 4 October 2026

The inspected AWS account was confirmed to match the running project's account without recording its identifier. SES sending is enabled but production access is false; there are zero email identities. Current quotas are 200 messages per 24 hours and one message per second, with zero messages sent in the preceding 24 hours. No identities, IAM credentials, DNS records or subscriptions were created, no terms were accepted, and no mail was sent.

## Cost and restrictions

Prefer SES à-la-carte sending: **$0.10 per 1,000 emails**, approximately $1 for 10,000 recovery emails, plus applicable message-data/transfer/tax charges. No dedicated IPs, global endpoints or paid deliverability add-ons are needed for this initial use. The current AWS pricing page says new account/region combinations default to **Essentials at $0.16 per 1,000** from July 2026, so the actual plan must be checked and the intended à-la-carte option explicitly selected after authorization. Do not assume a free tier or claim the lower price is already active. [AWS pricing](https://aws.amazon.com/ses/pricing/).

Sandbox mail can reach only verified recipient identities or the mailbox simulator. Public recovery requires AWS production-access approval, a verified sender, and a documented process for bounces and complaints. AWS aims to provide an initial response within 24 hours; approval and timing are not guaranteed. A project website and accurate transactional-use description are required for that request. [AWS sandbox and production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html).

## Work after the owner's decision

We can configure the regional sender identity, prepare exact DNS records for DKIM and domain verification, scope SMTP sending permissions to the sender, place regional SMTP credentials in protected secret storage, connect the already tested adapter, set up bounce/complaint handling, submit a truthful production-access request, and test delivery/reset end to end. Identity-verification email and production-access submissions require authorization as part of that connection. Do not derive SMTP credentials from the EC2 role's temporary AWS credentials; SMTP requires its own supported regional credentials. [AWS SMTP requirements](https://docs.aws.amazon.com/ses/latest/dg/send-email-smtp.html), [SMTP credentials](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html).

Needed from the owner: the existing domain they control and desired sender address, permission to configure SES, and access to add verification/DKIM DNS records (or the owner can add the supplied records). If no domain exists, a controlled email address can be verified for testing, but production domain alignment and deliverability should be settled before launch; no domain purchase is implied. [Identity verification](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html).

One decision question after application integration: **“May I configure Amazon SES for recovery emails in the existing AWS account, and which existing domain and sender address should it use?”** No passwords or API keys should be pasted into chat.

Until verified delivery and production access are ready, the application must continue to show email recovery as unavailable. Local SMTP tests and completed recovery code are not evidence of production email delivery.
