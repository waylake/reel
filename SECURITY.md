# Security Policy

## Supported versions

Only the latest release gets security fixes. Reel updates itself through Sparkle, so staying current is usually automatic.

| Version | Supported |
| --- | --- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report them privately through [GitHub Security Advisories](https://github.com/waylake/reel/security/advisories/new). Please include:

- What the issue is and what an attacker could do with it
- Steps to reproduce, or a proof of concept
- The Reel version and macOS version you tested on

You can expect an acknowledgement within a few days. Once the issue is confirmed, we'll work on a fix, ship it in a new release and credit you in the release notes (unless you'd rather stay anonymous).

## Scope

Examples of what's in scope:

- The Reel app and its update mechanism (Sparkle appcast and signatures)
- How Reel builds `yt-dlp` arguments from URLs and settings, including argument injection
- How Reel handles clipboard contents, dropped files and browser cookies

Out of scope: vulnerabilities in yt-dlp or FFmpeg themselves. Please report those upstream to [yt-dlp](https://github.com/yt-dlp/yt-dlp/security) or [FFmpeg](https://ffmpeg.org/security.html).
