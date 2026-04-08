# Delta VoiceIQ 2.0 - Home Assistant Integration

[![Home Assistant](https://img.shields.io/badge/Home%20Assistant-2024.1+-blue?logo=home-assistant)](https://www.home-assistant.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![HACS](https://img.shields.io/badge/HACS-Required-orange)](https://hacs.xyz)
[![VoiceIQ](https://img.shields.io/badge/VoiceIQ-Gen%202-green)](https://www.deltafaucet.com/voiceiq)

> A complete reverse-engineered integration of **Delta VoiceIQ Version 2** smart faucets with Home Assistant. Control your faucet, dispense precise amounts, track water usage, and manage auth tokens -- all without the official app.

## What This Does

- **On/Off control** via dashboard card, automations, or voice assistants
- **Metered dispensing** with preset containers (Glass, Coffee Pot, Sink) or custom ml amounts
- **Water usage tracking** with daily, weekly, monthly, and yearly sensors
- **Animated dashboard card** with water-fill icon, flow animations, and usage badge
- **Rich popup** (browser_mod) with dispense buttons, usage stats, and history graph
- **Browser-based token refresh** that eliminates mitmproxy for ongoing use
- **Token expiry warnings** via persistent notifications

## Screenshots

| Dashboard Card | Long-Press Popup | Token Refresh Page |
|:-:|:-:|:-:|
| ![Card](docs/images/card-off.png) | ![Popup](docs/images/popup.png) | ![Refresh](docs/images/token-refresh-page.png) |
| Animated water-fill icon with usage badge | Dispense buttons, usage stats, history | Browser-based token refresh tool |

| Card Flowing |
|:-:|
| ![Flowing](docs/images/card-flowing.png) |
| Bubble animation when faucet is on |

## Compatibility

| Component | Tested Version |
|-----------|---------------|
| VoiceIQ Module | Gen 2 (product ID: `DELTA2-VOICE`) |
| Module Firmware | 2.0.2.0 |
| DFC@Home App | 2.6.0 (iOS) |
| VoiceIQ API | v2/v3 on `device.deltafaucet.com` |
| Home Assistant | 2024.1+ (tested through 2026.4) |

**Gen 1 vs Gen 2:** This integration targets the **Generation 2 VoiceIQ module** and its API. The DFC@Home app now supports both Gen 1 and Gen 2 modules. The API endpoints should be the same, but Gen 1 has not been tested with this integration. If you have a Gen 1 module and try this, please open an issue with your results.

---

## Quick Start

1. Capture your VoiceIQ token using [mitmproxy](#initial-token-capture) (one-time)
2. Copy files from this repo into your HA config
3. Add your token, MAC address, and user ID to `secrets.yaml`
4. Restart Home Assistant
5. Add the dashboard card

---

## Repository Structure

```
delta-voiceiq-2.0-ha/
├── README.md
├── LICENSE
├── docs/
│   ├── API.md                         # Full API reference
│   └── AUTH.md                        # Authentication deep dive
├── packages/
│   └── delta_voiceiq.yaml             # All-in-one HA package
├── www/
│   └── delta-refresh.html             # Token refresh web page
├── scripts/
│   └── delta_token_exchange.sh        # Token exchange shell script
├── dashboard/
│   ├── card.yaml                      # Mushroom card config
│   └── popup.yaml                     # browser_mod popup config
└── secrets.yaml.example               # Template for secrets
```

---

## Prerequisites

**Hardware:**
- Delta VoiceIQ-enabled faucet (Touch2O manufactured after Jan 2018)
- VoiceIQ module connected to WiFi and registered at `device.deltafaucet.com`

**Home Assistant:**
- Home Assistant OS or Supervised (2024.1+)
- File Editor or Studio Code Server add-on
- Terminal & SSH add-on (for shell scripts)

**HACS Components:**
- [Mushroom Cards](https://github.com/piitaya/lovelace-mushroom)
- [card-mod](https://github.com/thomasloven/lovelace-card-mod)
- [browser_mod](https://github.com/thomasloven/hass-browser_mod) (optional, for popup)

**For initial token capture only:**
- [mitmproxy](https://mitmproxy.org/) on a computer
- DFC@Home app on your phone

---

## API Reference

Base URL: `https://device.deltafaucet.com`

### Required Headers

```
Authorization: Bearer <VoiceIQ JWT>
dfc-source: mobile
User-Agent: DFCatHome/2.6.0 CFNetwork/3860.400.51 Darwin/25.3.0
```

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/device/v3/ToggleWater?macAddress=MAC&toggle=on\|off` | POST | Turn faucet on/off |
| `/api/device/v2/Dispense?macAddress=MAC&milliliters=N` | POST | Dispense specific amount (ml) |
| `/api/device/v2/UsageReport?macAddress=MAC&interval=N` | GET | Usage (0=today, 1=week, 2=month, 3=year) |
| `/api/voice/v4/handWashMode` | POST | Hand wash mode |
| `/api/user/v2/UserInfo` | GET | User info, devices, containers |

See [docs/API.md](docs/API.md) for full details.

---

## Authentication

Delta uses **two completely separate** auth systems. Only VoiceIQ is needed.

| Property | VoiceIQ (for faucet) | DFC@Home (NOT for faucet) |
|----------|---------------------|--------------------------|
| Server | `device.deltafaucet.com` | `api.deltafaucet-cw.com` |
| Token lifetime | ~60 days | 15 min (with refresh) |
| Refresh token | No | Yes |
| Login | Apple/Google/Amazon | Azure AD B2C |

The VoiceIQ system has no refresh token. You must re-authenticate every ~60 days. The included browser-based refresh page makes this a 30-second process.

See [docs/AUTH.md](docs/AUTH.md) for the full deep dive.

---

## Initial Token Capture

You need mitmproxy **once** to get the initial token.

1. Install: `brew install mitmproxy` (macOS) or `pip install mitmproxy`
2. Run: `mitmweb --listen-port 8080`
3. Set your phone's WiFi proxy to your computer's IP:8080
4. Visit `http://mitm.it` on phone, install CA cert
5. iOS: Settings > General > About > Certificate Trust Settings > enable mitmproxy
6. Open DFC@Home app, sign in
7. In mitmweb, filter `device.deltafaucet.com`, copy the `Authorization: Bearer ...` token
8. Also grab MAC address and user ID from `/api/user/v2/UserInfo` response
9. Remove proxy from phone

---

## Home Assistant Setup

### Option A: Package (Recommended)

1. Copy `packages/delta_voiceiq.yaml` to `/config/packages/`
2. Enable packages in `configuration.yaml`:
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
3. Copy `www/delta-refresh.html` to `/config/www/`
4. Copy `scripts/delta_token_exchange.sh` to `/config/scripts/`
5. Run: `chmod +x /config/scripts/delta_token_exchange.sh`
6. Add to `secrets.yaml`:
   ```yaml
   delta_token: "Bearer eyJhbGciOi..."
   delta_mac_address: "YOUR_MAC_ADDRESS"
   delta_user_id: "YOUR_USER_ID"
   ```
7. Restart HA

### Option B: Manual

Copy each section from the package file into your existing `configuration.yaml`.

---

## Token Lifecycle: Expiry, Notification, and Refresh

The VoiceIQ token lasts ~60 days with **no refresh token**. Here's the full lifecycle:

### How You'll Know It's Expiring

1. **Dashboard badge:** The faucet card's popup shows a token status indicator with days remaining
2. **Template sensor:** `sensor.delta_token_expiry` always shows the days left (e.g. "59 days")
3. **Persistent notification:** An automation checks daily at 9:00 AM. When fewer than 7 days remain, you'll see a persistent notification in HA:

> **Delta Faucet Token Expiring Soon**
> Your Delta faucet API token expires in less than 7 days.
> Visit /local/delta-refresh.html to refresh it.

![Token Expiry Notification](docs/images/token-expiry-notification.png)

### How To Refresh (30 seconds)

When you get the warning, or any time you want to refresh:

1. Go to `http://<your-ha-ip>:8123/local/delta-refresh.html`

![Token Refresh Page](docs/images/token-refresh-page.png)

2. Enter your HA **long-lived access token** in the connection settings
   - Create one at: your HA profile (click your name bottom-left) > Long-Lived Access Tokens > Create Token
3. Click **Open Apple Sign-In** -- a new tab opens with Delta's login page
4. Sign in with your Apple ID (or Google/Amazon)
5. After authentication, the browser tries to redirect to `justaddwater://` and **fails** (this is expected)
6. Your browser URL bar now shows something like: `justaddwater://?code=delta.code.XXXXX&state=YYY`
7. **Copy the entire URL** from the address bar
8. Paste it into the input field on the refresh page
9. Click **Exchange Token**
10. The page polls for status. Within ~10 seconds you'll see either:
    - **Success:** "Token refreshed! Expires [date] ([days] days). Backup at secrets.yaml.bak"
    - **Error:** Details about what went wrong

### What Happens Behind the Scenes

The shell script (`delta_token_exchange.sh`):
1. Calls Delta's `PostAuth` endpoint with your code
2. Captures the 302 redirect containing a base64-encoded JWT
3. Decodes and validates the JWT
4. Backs up `secrets.yaml` to `secrets.yaml.bak`
5. Writes the new token to `secrets.yaml`
6. Updates the `exp_ts` timestamp in your automations
7. Pushes status to `input_text.delta_token_status` so the web page shows the result

### What If the Token Expires Completely?

If the token expires before you refresh, your REST commands will return 401 errors and the usage sensors will go `unknown`. The faucet itself still works manually and via Alexa/Google. Just refresh the token using the steps above and everything comes back online.

---

## Dashboard

The card uses Mushroom + card-mod for animated water-fill effects.
- **Tap** = toggle on/off
- **Long press** = popup with dispense buttons, usage stats, history

**Important:** browser_mod must be added as an integration (Settings > Devices & Services > Add Integration > Browser Mod), not just installed via HACS.

See `dashboard/card.yaml` and `dashboard/popup.yaml` for configs.

---

## Example Automations

### Morning Coffee Fill
```yaml
automation:
  - alias: "Morning Coffee"
    trigger:
      - platform: time
        at: "06:30:00"
    action:
      - service: rest_command.delta_faucet_dispense
        data:
          milliliters: 946
```

### Faucet Auto-Off Safety
```yaml
automation:
  - alias: "Faucet Auto-Off"
    trigger:
      - platform: state
        entity_id: input_boolean.delta_faucet_state
        to: "on"
        for:
          minutes: 5
    action:
      - service: rest_command.delta_faucet_off
      - service: input_boolean.turn_off
        target:
          entity_id: input_boolean.delta_faucet_state
```

---

## FAQ

**Q: 401 Unauthorized?** Token expired. Refresh at `/local/delta-refresh.html`.

**Q: Can I use the DFC@Home token?** No. Different systems, different tokens.

**Q: Gen 1 module?** Untested but likely works. Please report.

**Q: Dispense inaccurate?** Accuracy drops below 4oz. Faucet auto-stops at 4 min.

**Q: Popup not showing?** Add browser_mod as integration, not just HACS install.

---

## Disclaimer

Not affiliated with Delta Faucet or Masco Corporation. Use at your own risk. Automated water control could cause flooding if misused.

## Credits

Dashboard card badge theme and animations inspired by [Anashost's HA Animated Cards](https://github.com/Anashost/HA-Animated-cards/blob/main/appliances.md). Huge thanks to [@Anashost](https://github.com/Anashost) for the incredible work on animated Mushroom card styling.

MIT License.
