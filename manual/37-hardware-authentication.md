# Hardware authentication

### Fingerprint authentication

A lot of laptops come with a fingerprint sensor to do authentication. You can use this with Omarchy by running _Setup > Security > Fingerprint_ in the Omarchy menu (`Super + Space`).

That'll install the fingerprint package, collect your print, verify it, and you'll be set to go using your fingerprint to unlock from the lock screen (which you can trigger with `Super + Ctrl + L`), enter sudo mode, and authorize system prompts.

When your laptop lid is closed, the fingerprint prompt is automatically skipped, so you go straight to the password prompt instead of waiting on a sensor you can't reach. If you otherwise need to work on an external keyboard that doesn't have a sensor, just hit `CTRL + C`, when you're prompted for your fingerprint during `sudo`.

You can remove the fingerprint authentication under _Remove > Security > Fingerprint_ in the Omarchy menu.

### Fido2 authentication

If you're using a Fido2 device, you can set it up for `sudo` authentication using _Setup > Security > Fido2_ in the Omarchy menu (`Super + Space`). It covers `sudo` and system authorization prompts, though, not unlocking your computer.

You can remove the fido2 authentication under _Remove > Security > Fido2_ in the Omarchy menu.

### Facial recognition (Windows Hello)

If your laptop has an infrared (IR) facial recognition camera (such as on the Microsoft Surface Laptop Studio), you can set up hands-free biometric authentication using _Setup > Security > Face Unlock_ in the Omarchy menu (`Super + Space`) or by running `omarchy setup security face`.

Features include:
* **True hands-free unlock**: Authenticates automatically in the background on the lock screen without needing to press Enter or type a password.
* **Instant password fallback**: Typing your master password unlocks immediately with zero delay.
* **Configurable lock grace delay**: Gives you time to turn or step away before the camera begins scanning (default: 4 seconds).
* **Panic Lockdown (`Super + Alt + L`)**: Immediately locks the session and suppresses all biometrics, requiring your master password.
* **Negative feedback & audio chimes**: Visual head-shake animation and subtle audio chimes for match and rejection.
* **Anti-spoofing & intruder protection**: Active IR LED strobe rejection of 2D screen replays and silent snapshots on repeated failed attempts.
* **System elevation**: Uses face recognition for terminal `sudo` and graphical Polkit prompts.

For full instructions, calibration tips, and troubleshooting, select _User Manual & Reference Guide_ inside the Face Unlock menu or run `omarchy setup security face --manual`.
