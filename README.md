# AlexaAssist

A menu bar controller for your Echo Dot: timers, alarms and reminders from your Mac.

> **Unofficial. Not affiliated with Amazon. May stop working if Amazon changes its service.**

- Lives only in the menu bar (no Dock icon, no main window).
- Pick an Echo, start a timer (presets or custom, optional label), set an alarm or reminder.
- Everything is created *on Alexa*, so it shows in the Alexa app too, and the menu bar counts down the next timer.
- See upcoming timers / alarms / reminders and cancel any of them.

## Requirements

macOS 15+, an Amazon account with an English-language Echo device.

## Install

**From source:** clone, open `AlexaAssist.xcodeproj` in Xcode 16+, Run.

**Release DMG (unsigned):** first launch → System Settings → Privacy & Security → **Open Anyway**.

Your Amazon site (amazon.com, .co.uk, .de, .in, …) is detected automatically after sign-in. Commands are sent in English,
so the Echo's language must be English.

## How it works

You sign in on Amazon's own page inside the app; AlexaAssist registers itself as an Alexa app device
(it appears as "…'s AlexaAssist" under *Your Devices* on Amazon; remove it there after signing out if you like)
and keeps only the refresh token, in your Keychain. Actions are sent as text commands ("set a timer for 10 minutes").

## Development

```sh
xcodebuild test -project AlexaAssist.xcodeproj -scheme AlexaAssist   # or ⌘U in Xcode
```

Logs: Console.app, filter on subsystem `dev.alexaassist` (status codes and endpoint names only, never tokens).

## Credits

Protocol knowledge from [alexa-remote2](https://github.com/Apollon77/alexa-remote) / alexa-cookie2 (MIT)
and [aioamazondevices](https://github.com/chemelli74/aioamazondevices) (Apache-2.0).

## License

MIT
