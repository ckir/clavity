# Security Policy

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.** Report privately via GitHub's
private vulnerability reporting — the **"Report a vulnerability"** button under the **Security** tab
of [github.com/ckir/clavity](https://github.com/ckir/clavity/security) — or by contacting the
maintainer directly.

Please include: the affected product/component, the version, a description of the issue, and
reproduction steps if you have them. You can expect an acknowledgement within a reasonable time;
please allow time to investigate and ship a fix before any public disclosure.

## Scope

clavity ships installers and drives external tools (Antigravity, Ghidra, a headless JVM, coding
agents) over local IPC and a signal bus. In scope: the clavity code itself, its installers, its
plugins/hooks/skills, and the MCP bridge. Out of scope: vulnerabilities in the external tools
themselves (Antigravity, Ghidra, the JDK, the agents) — report those to their respective vendors.

## Supported versions

Security fixes target the latest released version of each product. Older versions are not maintained.
