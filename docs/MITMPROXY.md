# mitmproxy Setup Guide for Delta VoiceIQ Token Capture

This guide walks you through using mitmproxy to intercept the DFC@Home app traffic and capture your VoiceIQ authentication token. You only need to do this **once** for the initial setup. After that, use the browser-based token refresh page.

## What You Need

- A Mac, Windows, or Linux computer
- Your phone (iOS or Android) with the DFC@Home app installed
- Both devices on the same WiFi network

## Overview

The process works like this: mitmproxy acts as a "man in the middle" between your phone and Delta's servers. When the DFC@Home app sends requests, mitmproxy captures them so you can see the authentication token, MAC address, and user ID.

```
Phone (DFC@Home app)  -->  mitmproxy (your computer)  -->  Delta servers
                              |
                         You read the
                         token from here
```

---

## Step 1: Install mitmproxy

### macOS
```bash
brew install mitmproxy
```

If you don't have Homebrew, install it first: https://brew.sh

### Windows
Download the installer from https://mitmproxy.org/ and run it.

### Linux
```bash
pip install mitmproxy
```

---

## Step 2: Start mitmproxy

Open a terminal and run:

```bash
mitmweb --listen-port 8080
```

This starts two things:
- A proxy server on port 8080
- A web interface that opens in your browser at `http://127.0.0.1:8081`

Leave this running.

### Find Your Computer's IP Address

**macOS:**
```bash
ipconfig getifaddr en0
```

**Windows:**
```
ipconfig
```
Look for "IPv4 Address" under your WiFi adapter.

**Linux:**
```bash
hostname -I
```

Write down this IP (e.g., `192.168.1.100`).

---

## Step 3: Configure Your Phone's Proxy

### iOS

1. Open **Settings > Wi-Fi**
2. Tap the **info (i) button** next to your connected WiFi network
3. Scroll down to **HTTP Proxy**
4. Select **Manual**
5. Set:
   - Server: your computer's IP (e.g., `192.168.1.100`)
   - Port: `8080`
   - Authentication: Off
6. Tap **Save**

### Android

1. Open **Settings > Network & Internet > Wi-Fi**
2. Long-press your connected WiFi network, tap **Modify network**
3. Tap **Advanced options**
4. Set Proxy to **Manual**
5. Set:
   - Proxy hostname: your computer's IP (e.g., `192.168.1.100`)
   - Proxy port: `8080`
6. Tap **Save**

---

## Step 4: Install the mitmproxy Certificate

Your phone needs to trust mitmproxy's certificate to intercept HTTPS traffic.

1. On your phone's browser, go to: **http://mitm.it**
2. Tap the button for your platform (Apple or Android)

### iOS Certificate Setup

1. After downloading, go to **Settings > General > VPN & Device Management**
2. Tap "mitmproxy", then tap **Install**
3. **IMPORTANT:** Now go to **Settings > General > About > Certificate Trust Settings**
4. Find "mitmproxy" and **toggle it ON**
5. Confirm by tapping **Continue**

Without steps 3-5, HTTPS interception will not work on iOS.

### Android Certificate Setup

1. The certificate file should download automatically
2. Go to **Settings > Security > Encryption & credentials > Install a certificate**
3. Select **CA certificate**
4. Find and select the downloaded mitmproxy certificate

---

## Step 5: Verify the Proxy Works

1. On your phone, open any website (e.g., `https://google.com`)
2. Look at the mitmweb interface on your computer (`http://127.0.0.1:8081`)
3. You should see requests appearing

If you see requests, the proxy is working.

---

## Step 6: Capture the Token

1. On your phone, open the **DFC@Home** app
2. Sign in or navigate around to generate API traffic

3. On your computer, in the mitmweb interface:
   - Click the **Search/Filter** bar at the top
   - Type: `device.deltafaucet.com`
   - Press Enter

4. Click on any request. In the **Request** tab, look at **Headers**

5. Find the `Authorization` header:
   ```
   Authorization: Bearer eyJhbGciOiJSUzI1NiIsIn...very_long_string
   ```

6. **Copy the entire value after "Bearer "**. This is your VoiceIQ JWT token.

---

## Step 7: Capture Your Device Info

1. In mitmweb, look for a request to `/api/user/v2/UserInfo`
2. Click on it, then click the **Response** tab
3. In the response body (JSON), find:
   - `macAddress` - your faucet's MAC address (e.g., `C8F5D6604AA0`)
   - `userId` - your VoiceIQ user ID
   - `containers` - your custom dispense containers
   - `modes` - your custom modes

Write down the MAC address and user ID.

---

## Step 8: Verify Your Token

Go to https://jwt.io and paste your token.

In the decoded payload, verify:
- `aud` is `device.deltafaucet.com`
- `exp` is approximately 60 days in the future

Convert the `exp` timestamp:
```bash
# macOS
date -r 1780809002

# Linux
date -d @1780809002
```

---

## Step 9: Clean Up

**IMPORTANT: Remove the proxy from your phone.**

### iOS
Settings > Wi-Fi > tap (i) on your network > HTTP Proxy > Off

### Android
Settings > Wi-Fi > long-press network > Modify > Advanced > Proxy > None

### Optional: Remove the Certificate

**iOS:** Settings > General > VPN & Device Management > mitmproxy > Remove Profile

**Android:** Settings > Security > Trusted credentials > User tab > mitmproxy > Remove

### Stop mitmproxy
In your terminal, press `Ctrl+C`.

---

## Troubleshooting

**"mitm.it" shows a blank page:**
The proxy isn't working. Check that your phone's proxy settings point to the correct IP and port 8080.

**Requests show "connection error":**
The certificate isn't trusted. On iOS, make sure you completed the trust step in Settings > General > About > Certificate Trust Settings.

**No requests to device.deltafaucet.com:**
Force-close and reopen the DFC@Home app. Sign out and back in.

**Token expired:**
Tokens last approximately 60 days. After initial capture, use the browser-based refresh page instead of mitmproxy.

---

## What's Next?

Now that you have your token, MAC address, and user ID, head back to the [main README](../README.md#home-assistant-setup) to set up Home Assistant.
