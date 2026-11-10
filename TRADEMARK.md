# Trademark

The licence grants copyright and patent rights. It grants **no right to the
name** — Apache-2.0 §6 says so explicitly:

> This License does not grant permission to use the trade names, trademarks,
> service marks, or product names of the Licensor, except as required for
> reasonable and customary use in describing the origin of the Work.

This file is the separate statement that section contemplates.

## Marks

- **The project name**: Rigorix, and the wordmark.
- **The published coordinates**, because people type them:
  `rigorix-schemas`, `rigorix-verifier`, `rigorix-client` (crates.io, npm, PyPI),
  `eu.rigorix:rigorix-verifier` (Maven Central), and the Go module path
  `github.com/arman-jalili/rigorix-sdk/go`.

## Permitted without asking

- **Nominative use.** Saying that your product uses this SDK, or that it
  verifies Rigorix audit envelopes, is describing your product's origin — which
  is exactly what §6 reserves.
- **Stating compatibility**, e.g. "implements the Rigorix envelope v2 contract",
  "compatible with rigorix-verifier 0.9".
- **Redistributing unmodified packages** under their own names, which is what
  every dependency manager does anyway.
- **Referring to this repository by its name** in documentation, articles and
  issue trackers.
- **Forking the code.** The licence permits it; see below for the name.

## Requires permission

- **A modified distribution presented under the name.** A fork that changes the
  behaviour must not ship as "Rigorix" or as a `rigorix-*` package, because a
  reader would attribute the change to this project.
- **A hosted service presented as the project**, or as its official service.
- **Any use implying endorsement or certification** by this project.
- **Use in a company or product name**, or as a domain name.
- **A logo or wordmark**, which is not covered by the licence at all.

## How to ask

Open a private GitHub security advisory on this repository
(`Security → Report a vulnerability`, subject "trademark") — the same private
channel used for security and conduct reports, monitored by the maintainer on
call. Permission is granted or refused **in writing**, and a refusal states what
would be acceptable instead. Silence is not permission.

## Answering the common question

*May I fork this and call it Rigorix?* **No.** You may fork it, modify it, sell
support for it, and say it is "based on Rigorix" — but the modified thing needs
its own name. Unmodified redistribution keeps the name.

This file is not legal advice; it is the project's stated position, so a reader
does not have to guess.