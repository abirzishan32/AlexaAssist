# Amazon endpoints used by AlexaKit

Matched line-by-line against the source of **aioamazondevices** (`login.py`, `http_wrapper.py`, `const/http.py`,
`implementation/sequence.py`, `implementation/notification.py`) and **alexa-cookie2 / alexa-remote2**
(`alexa-cookie.js`, `lib/proxy.js`, `alexa-remote.js`) on 2026-10-18.
Checked live: Amazon serves its normal sign-in page for the generated OAuth URL. Not yet run end-to-end with a real account.

| Step | Request | Source |
|---|---|---|
| Sign-in page | `GET https://www.amazon.com/ap/signin?…` with cookies `frc`, `map-md`, `amzn-app-id` pre-set on `.amazon.com` | aioamazondevices `_build_oauth_url`, `_build_init_cookies` |
| Redirect | `https://www.amazon.com/ap/maplanding?openid.oa2.authorization_code=…` | both |
| Register | `POST https://api.amazon.com/auth/register` (JSON, `use_global_authentication`, `user_context_map.frc`) → `response.success.tokens.bearer.refresh_token`, `extensions.customer_info.home_region` | aioamazondevices `_register_device` |
| Auth cookies | `POST https://api.amazon.com/auth/token` (form, `requested_token_type=auth_cookies`, `domain=www.amazon.<x>`) → `response.tokens.cookies` | aioamazondevices `refresh_data` |
| Amazon site | `GET https://alexa.amazon.com/api/welcome` → `alexaHostName` (home_region `FE` → amazon.co.jp) | aioamazondevices `_get_alexa_domain` |
| csrf | first of `/api/language`, `/spa/index.html`, … that sets the `csrf` cookie; sent back as `csrf` header | alexa-cookie2 `csrfOptions` |
| Customer ID | `GET /api/users/me` → `id` | aioamazondevices `obtain_account_customer_id` |
| Devices | `GET /api/devices-v2/device?cached=false`, keep those with capability `TIMERS_AND_ALARMS` | both |
| Command (timers, alarms) | `POST /api/behaviors/preview`, SerialNode → `Alexa.TextCommand`, payload `{deviceType, deviceSerialNumber, locale, customerId, skillId: amzn1.ask.1p.tellalexa, text}` | aioamazondevices `_build_operation_node` |
| Reminder | `PUT /api/notifications/null` with `{type: "Reminder", reminderLabel, alarmTime (ms), originalDate, originalTime, deviceSerialNumber, deviceType, status: "ON", …}` | alexa-remote2 `createNotificationObject` / `createNotification` |
| Alerts | `GET /api/notifications`; timer `triggerTime`, reminder `alarmTime`, alarm `originalDate`+`originalTime` | aioamazondevices `_parse_next_occurrence` |
| Cancel | `DELETE /api/notifications/{id}` with the notification JSON as body | alexa-remote2 `deleteNotification` |

Known simplification: repeating alarms show their time of day only (weekday RRULEs aren't evaluated).
