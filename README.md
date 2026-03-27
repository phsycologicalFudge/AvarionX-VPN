<div align="center">

<img src="https://github.com/phsycologicalFudge/AvarionX-VPN/blob/main/assets/icons/icon.png" width="140" alt="ColourSwift logo">

# AvarionX Secure VPN

A privacy focused VPN client for Android, designed to provide secure connections, modern protocols, and a clean user experience without intrusive tracking or advertising.

Available on Google Play and GitHub.

<br>

<img src="https://img.shields.io/github/downloads/phsycologicalFudge/AvarionX-VPN/total?label=App%20downloads">
<img src="https://img.shields.io/github/v/release/phsycologicalFudge/AvarionX-VPN?label=App%20release">
<img src="https://img.shields.io/github/license/phsycologicalFudge/AvarionX-VPN">

<br>

<a href="https://play.google.com/store/apps/details?id=com.colourswift.avarionxvpn">
  <img src="https://play.google.com/intl/en_gb/badges/static/images/badges/en_badge_web_generic.png" height="80">
</a>

</div>

## Screenshots

<div align="center">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/1.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/2.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/3.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/4.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/5.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/6.jpg" width="220">
  <img src="https://raw.githubusercontent.com/phsycologicalFudge/AvarionX-VPN/main/assets/gitImages/7.jpg" width="220">

</div>

## Overview

AvarionX Secure VPN allows Android devices to connect to secure VPN servers using modern encrypted protocols.

The application is designed to be simple to use while still supporting advanced networking backends and transport methods.

Key features:

- Secure VPN tunneling
- Multiple backend protocol options
- Global server locations
- Low overhead Android implementation
- Clean UI with no intrusive tracking
- Compatible with modern Android networking APIs

## Join the Discord

https://discord.gg/VYubQJfcYM

## Protocols and Networking

The VPN client supports multiple transport backends.

### WireGuard

WireGuard is the primary protocol used for high performance encrypted tunneling.

It offers:

- Modern cryptography
- Low overhead
- Fast connection establishment
- Efficient roaming support

## Networking Components

This project integrates and builds upon several open-source networking tools.

External components referenced in this project include:

### Hysteria

High performance proxy built on QUIC.

https://github.com/apernet/hysteria

### Tun2Socks

A TUN interface to SOCKS bridge used for routing VPN traffic through proxy transports.

https://github.com/xjasonlyu/tun2socks

### Amnezia WireGuard

An obfuscated variant of the WireGuard protocol designed to resist traffic identification.

https://github.com/amnezia-vpn/amneziawg

These projects remain the property of their respective authors.

## Download

Get the latest APK from GitHub Releases:

https://github.com/phsycologicalFudge/AvarionX-VPN/releases

## Privacy

The VPN client is designed with a minimal data collection philosophy.

- Strict *No Activity Logs* policy. Encrypted traffic content is never inspected or logged.
- No ads, analytics, or tracking libraries are included in the application.

## The architecture

### Colourswift Core

Authentication, account policy enforcement etc, are handled by ColourSwift Core, which runs on Cloudflare infrastructure. 

#### How does it work?
The client generates a device identifier, this is a random value for anonymous users or an account-linked identifier when signed in.

When connecting, the client sends this identifier to ColourSwift Core to request connection details for a selected region.
The backend responds with temporary session data and server configuration. 

The client then establishes a direct connection to the VPN server using this information.

ColourSwift Core is responsible for authentication and server assignment. It does not proxy, inspect, or handle user traffic.

### CoreDNS

DNS services are handled by a DNS worker on Cloudflare, controlled by Colourswift Core.

#### How does it work?
In full VPN mode, DNS requests are handled by the VPN server.
In DNS-only mode, the client communicates directly with the DNS service over HTTPS. Requests are processed by a Cloudflare Worker and filtered based on the user’s plan and settings.

## My Promise

The system is designed to follow modern data minimization practices while maintaining the *No Activity Logs* policy.
