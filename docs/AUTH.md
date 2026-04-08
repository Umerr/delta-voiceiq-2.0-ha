# Delta VoiceIQ Authentication

## Two Separate Systems

### VoiceIQ (device.deltafaucet.com) -- USED FOR FAUCET CONTROL
- Token issuer: `token.deltafaucet.com`
- Token audience: `device.deltafaucet.com`
- Lifetime: ~60 days
- NO refresh token
- Login: Apple / Google / Amazon

### DFC@Home (api.deltafaucet-cw.com) -- NOT FOR FAUCET CONTROL
- Azure AD B2C at `login.deltafaucet-cw.com`
- Client ID: `9c38647c-4bfb-4d2f-9a4d-5101d12a7f4f`
- 15-min access / 14-day refresh token
- Standard OAuth2 refresh flow
- Tokens are REJECTED by VoiceIQ API

## VoiceIQ Auth Flow (Apple Sign-In)

1. App opens `device.deltafaucet.com/Auth/Login?provider=apple&response_type=code&scope=profile_email&state=RANDOM&redirect_uri=justaddwater://`
2. Delta redirects to Apple with `client_id=con.deltafaucet.device`
3. User authenticates
4. Apple POSTs to `device.deltafaucet.com/auth/applecallback`
5. Delta redirects to `justaddwater://?code=delta.code.XXXXX&state=YYY`
6. App calls `device.deltafaucet.com/Auth/PostAuth?code=delta.code.XXXXX&state=YYY`
7. Delta returns 302 with base64 token in URL: `https://device.deltafaucet.com/#/auth/BASE64_JSON`
8. Decoded JSON contains `accessToken`, `userId`, metadata

## Browser-Based Refresh

Since `justaddwater://` fails in browsers, you can copy the delta code from the URL bar and exchange it manually via the included shell script and HTML page.
