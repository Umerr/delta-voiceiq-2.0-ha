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

Or use your package manager:
```bash
# Ubuntu/Debian
sudo apt install mitmproxy

# Fedora
sudo dnf install mitmproxy
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

Leave this running. The web interface is where you'll see all the intercepted traffic.

### Find Your Computer's IP Address

You'll need your computer's local IP address for the next step.

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

Write down this IP (e.g., `192.168.1.100`). You'll use it in the next step.

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
6. Tap **Save** (top right)

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
2. You should see a page with download buttons for different platforms
3. Tap the button for your platform (Apple or Android)

### iOS Certificate Setup

1. After downloading, go to **Settings > General > VPN & Device Management** (or "Profiles" on older iOS)
2. You'll see "mitmproxy" listed under Downloaded Profile
3. Tap it, then tap **Install** (enter your passcode if prompted)
4. Tap **Install** again to confirm
5. **IMPORTANT:** Now go to **Settings > General > About > Certificate Trust Settings**
6. Find "mitmproxy" and **toggle it ON**
7. Confirm by tapping **Continue**

Without step 5-7, HTTPS interception will not work on iOS.

### Android Certificate Setup

1. The certificate file should download automatically
2. Go to **Settings > Security > Encryption & credentials > Install a certificate**
3. Select **CA certificate**
4. Find and select the downloaded mitmproxy certificate
5. Confirm the installation

---

## Step 5: Verify the Proxy Works

Before opening the DFC@Home app, verify everything is working:

1. On your phone, open any website in Safari/Chrome (e.g., `https://google.com`)
2. Look at the mitmweb interface on your computer (`http://127.0.0.1:8081`)
3. You should see requests appearing in the flow list

If you see requests, the proxy is working. If not, double-check:
- Both devices are on the same WiFi network
- The proxy IP and port are correct
- The certificate is installed AND trusted

---

## Step 6: Capture the Token

1. On your phone, open the **DFC@Home** app
2. Sign in to your account (or just open the app if already signed in)
3. Navigate around the app (view your faucet, check usage, etc.) to generate API traffic

4. On your computer, in the mitmweb interface:
   - Click the **Search/Filter** bar at the top
   - Type: `device.deltafaucet.com`
   - Press Enter to filter

5. You should see several requests to `device.deltafaucet.com`. Click on any one of them.

6. In the request details panel, look at the **Request** tab, then **Headers**

7. Find the `Authorization` header. It will look like:
   ```
   Authorization: Bearer eyJhbGciOiJSUzI1NiIsIn...very_long_string
   ```

8. **Copy the entire value after "Bearer "** (the long string starting with `eyJ`). This is your VoiceIQ JWT token.

---

## Step 7: Capture Your Device Info

While you have the traffic captured, you also need your faucet's MAC address and user ID.

1. In mitmweb, look for a request to `/api/user/v2/UserInfo`
2. Click on it, then click the **Response** tab
3. In the response body (JSON), find:
   - `macAddress` - your faucet's MAC address (e.g., `C8F5D6604AA0`)
   - `userId` - your VoiceIQ user ID (a hex string)
   - `containers` - your custom dispense containers and their sizes
   - `modes` - your custom modes (hand wash, etc.)

Write down the MAC address and user ID. You'll need them for the Home Assistant setup.

---

## Step 8: Verify Your Token

Go to https://jwt.io and paste your token in the "Encoded" field on the left.

In the decoded payload on the right, verify:
- `aud` (audience) is `device.deltafaucet.com`
- `exp` (expiration) is a Unix timestamp approximately 60 days in the future
- The token has not expired

You can convert the `exp` timestamp to a readable date:
```bash
# macOS
date -r 1780809002

# Linux
date -d @1780809002
```

---

## Step 9: Clean Up

**IMPORTANT: Remove the proxy from your phone after you're done.**

### iOS
1. Settings > Wi-Fi > tap (i) on your network > HTTP Proxy > Off

### Android
1. Settings > Wi-Fi > long-press network > Modify > Advanced > Proxy > None

### Optional: Remove the Certificate

If you want to remove the mitmproxy certificate from your phone:

**iOS:** Settings > General > VPN & Device Management > mitmproxy > Remove Profile

**Android:** Settings > Security > Encryption & credentials > Trusted credentials > User tab > mitmproxy > Remove

### Stop mitmproxy

In your terminal, press `Ctrl+C` to stop mitmproxy.

---

## Troubleshooting

**"mitm.it" shows a blank page or error:**
The proxy isn't working. Check that your phone's proxy settings point to the correct IP and port 8080, and that both devices are on the same WiFi.

**Requests show up but all are "connection error":**
The certificate isn't trusted. On iOS, make sure you completed the trust step in Settings > General > About > Certificate Trust Settings.

**No requests to device.deltafaucet.com:**
The DFC@Home app may be using certificate pinning on newer versions. Try:
- Force-closing and reopening the app
- Signing out and back in
- If the app refuses to connect entirely, it may have certificate pinning that blocks mitmproxy

**Token expired or about to expire:**
Tokens last approximately 60 days. After the initial capture, use the browser-based refresh page at `/local/delta-refresh.html` instead of mitmproxy.

---

## What's Next?

Now that you have your token, MAC address, and user ID, head back to the [main README](../README.md#home-assistant-setup) to set up Home Assistant.
