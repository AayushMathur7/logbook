# Security

## Reporting a security issue

If you find a security or privacy issue in Log Book, please do not post the details in a public issue first.

Until a dedicated security contact exists, use a private channel you control for initial disclosure.

When reporting an issue, include:

- what happened
- how to reproduce it
- which macOS version you tested
- whether the issue affects stored local data, permissions, or model traffic

## Good reports for this project

Useful reports include:

- unexpected network traffic
- local data stored somewhere it should not be
- permission handling bugs
- privacy filter bypasses
- shell integration issues that capture more than intended
- file watching or browser capture exposing data that should have been excluded

## Current security model

The current project aims to reduce risk by keeping things simple:

- capture is local
- storage is local
- model calls are limited to a local Ollama host
- high-risk sources like screenshots, keystrokes, audio, and camera input are not captured

## Response expectations

This repository does not yet define formal response SLAs, CVE handling, or a supported-version policy.

Before a wider public launch, add:

- a dedicated security contact
- a supported versions policy
- a basic disclosure and fix process
