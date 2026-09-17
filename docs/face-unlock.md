# Omarchy Face Unlock — User Manual & Technical Reference

Welcome to the comprehensive guide for Windows Hello-style biometric facial recognition on Omarchy. This system brings fast, secure, hands-free authentication to Arch Linux and Hyprland on laptops equipped with infrared (IR) cameras (such as the Microsoft Surface Laptop Studio).

---

## 1. System Overview & Architecture

### How Biometric Face Unlock Works
Omarchy decouples password verification from background biometrics using two independent PAM flows running concurrently in Quickshell:

```
                  ┌─────────────────────────────────────┐
                  │      Lock Screen (Quickshell)       │
                  └──────────────────┬──────────────────┘
                                     │
           ┌─────────────────────────┴─────────────────────────┐
           ▼                                                   ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│     Foreground Password       │               │     Background Biometrics     │
│  /etc/pam.d/omarchy-lock-     │               │  /etc/pam.d/omarchy-lock-     │
│           password            │               │          fingerprint          │
└──────────────┬────────────────┘               └──────────────┬────────────────┘
               │ (typed by user)                               │ (background)
               ▼                                               ▼
       Immediate Unlock                             Grace Delay (default: 4s)
        (zero latency)                                         │
                                                               ▼
                                                       pam_howdy.so (IR)
                                                               │
                                                               ▼
                                                       Instant Unlock on
                                                       Verified Face Match
```

* **Instant Password Fallback:** You never have to wait for the camera. Entering your password and pressing <kbd>Enter</kbd> validates against `/etc/pam.d/omarchy-lock-password` and unlocks immediately with 0ms delay.
* **Hands-Free Background Scanning:** `/etc/pam.d/omarchy-lock-fingerprint` executes Howdy in the background, utilizing the hardware IR sensor (`/dev/video2`) to scan your face without requiring keyboard input.

---

## 2. Shortcuts & Lock Operations

| Shortcut / Action | Function | Behavior & Description |
| :--- | :--- | :--- |
| <kbd>Super + Ctrl + L</kbd> | **Normal Lock** | Locks the screen with the configured grace delay (default: 4s). Gives you time to turn or walk away before the camera scans. |
| <kbd>Super + Alt + L</kbd> | **Panic / Lockdown** | **Immediate emergency lock.** Suppresses all biometrics (IR camera and fingerprint). Forces master password only. Locks 1Password vaults and resets keyboard layout. |
| <kbd>Type Password + Enter</kbd> | **Master Unlock** | Instantly unlocks desktop at any time, bypassing or interrupting active scans. |
| <kbd>Empty Enter</kbd> | **Rescan Trigger** | When scanning is paused after repeated misses, pressing <kbd>Enter</kbd> immediately wakes the IR camera with 0ms delay to scan again. |
| <kbd>Esc</kbd> | **Clear / Dismiss** | Clears failed password notifications or exits the lock preview overlay. |

---

## 3. Visual Indicators & Audio Feedback

The lock screen features an animated Windows Hello badge positioned above the password field:

```
                    ┌─────────────────────────┐
                    │      (   radar  )       │
                    │   ┌───────────────┐     │
                    │   │    \uf118     │     │
                    │   │  laser sweep  │     │
                    │   └───────────────┘     │
                    │      (  pulse  )        │
                    └─────────────────────────┘
                         Looking for you...
```

### Badge Status Glyphs

| Glyph / Icon | Color | State | What is happening |
| :---: | :--- | :--- | :--- |
| **``** | Accent / Text | **Idle / Delay** | Machine is locked; waiting out the grace delay before powering the camera. |
| **``** + Laser | Blue / Accent | **Scanning** | Dual radar rings pulse outward; laser line sweeps down badge while IR camera processes facial features. |
| **`󰄬`** | `#50fa7b` (Green) | **Matched** | Facial identity verified! Accompanied by ascending harmonic chime; unlocks desktop in 350ms. |
| **`󰅙`** | `#ff5555` (Red) | **Rejected** | Face not recognized. Badge shakes left/right ($\pm 10\text{px}$) with descending reject audio chime. |
| **`󰌾`** | Muted Accent | **Lockdown** | Panic lockdown active. All biometrics disabled; master password required to enter. |

### Audio Chimes
* **Match Chime (`face-match.wav`):** Ascending harmonic chime ($D_5 \rightarrow A_5$) synthesized to notify you that biometric authentication succeeded.
* **Reject Chime (`face-reject.wav`):** Descending two-tone reject chime ($G_3 \rightarrow E\flat_3$) indicating biometric mismatch.
* Audio can be toggled on/off at any time in the management UI or via:
  ```bash
  echo off > ~/.config/omarchy/face-unlock-sound   # disable chimes
  echo on  > ~/.config/omarchy/face-unlock-sound   # enable chimes
  ```

---

## 4. Advanced Security & Protections

### 1. Anti-Spoofing & Liveness Guard
Physical 2D printed photographs and smartphone screen replays are blocked using four defensive layers:
1. **Active IR Strobing:** `linux-enable-ir-emitter` pulses active 850nm/940nm infrared LEDs. Human skin exhibits unique subsurface light scattering under IR, whereas smartphone screens reflect and photo prints absorb IR uniformly.
2. **Dark Frame Filter (`dark_threshold = 50.0`):** Rejects pitch-black or obscured frames, preventing blind spoofing.
3. **YuNet 3D Landmark Geometry (`yunet_score_threshold = 0.82`):** Validates genuine 3D facial depth and landmark positions before matching embeddings.
4. **CLAHE Contrast Equalization (`clahe_enabled = true`):** Normalizes histogram curves across harsh shadows and low ambient light.

### 2. Intruder / Snooper Snapshot Guard
If an unauthorized person attempts to gain access while your computer is locked:
* Quickshell maintains a failure counter for face mismatches and incorrect passwords.
* On the **3rd consecutive failed attempt** (and every subsequent failure), `ffmpeg` silently captures a frame from the color webcam (`/dev/video0`) to:
  ```
  ~/.local/state/omarchy/intruder-snapshots/intruder-YYYYMMDD-HHMMSS.jpg
  ```
* Capture is executed silently under unprivileged user permissions (via standard `systemd-logind` device uaccess) so the intruder receives no warning.
* When you legitimately unlock the machine with your password, a high-priority desktop notification alerts you:
  ```
  Security Alert: 3 failed unlock attempt(s) detected while locked.
  Snapshots saved to ~/.local/state/omarchy/intruder-snapshots/
  ```

### 3. Battery & Camera Standby Protection
To prevent battery depletion if you walk away from your desk while the lock screen remains illuminated:
* The background face scanner is limited to **2 consecutive attempts**.
* If unrecognized after 2 attempts, the IR camera powers down into standby.
* The screen displays: *"Face scan paused — press Enter to scan"*.
* Pressing an empty <kbd>Enter</kbd> immediately wakes the camera with 0ms grace delay to scan your face.

### 4. Clamshell Mode Protection
When connected to an external monitor and the laptop lid is closed:
* `omarchy-hw-laptop-closed` detects the closed lid state.
* Quickshell and PAM suppress camera initialization completely, preventing unnecessary heat generation inside the closed chassis.

---

## 5. Adaptive Multi-Condition Calibration

For reliable recognition regardless of lighting or posture, use the **Adaptive Multi-Condition Calibration Wizard**:

```bash
omarchy setup security face  # Select Option 2
```

The wizard guides you through 4 distinct real-world lighting and posture states:

| Step | Profile Name | Optimal Capture Conditions |
| :---: | :--- | :--- |
| **1** | `regular` | Sit normally facing the screen with standard daylight or office lighting. |
| **2** | `dim-night` | Dim or extinguish room lights to calibrate pure active IR sensor illumination. |
| **3** | `tilted-lap` | Tilt the laptop screen back as if using it on your lap or coffee table (angled from below). |
| **4** | `alt-expression` | Wear reading glasses or put on a natural smile to capture facial elasticity variations. |

---

## 6. System-Wide Biometric Integration

Face unlock is not restricted to the lock screen; it integrates across your entire Omarchy experience:

### Terminal Elevation (`sudo`)
Whenever a terminal command requires `sudo`, the IR camera activates automatically. You will see the IR emitter pulse and authenticate hands-free without typing your password.
* *Bypass / Cancel:* If you want to use your password instead, press <kbd>Ctrl + C</kbd> when prompted to abort Howdy and drop to password entry.

### Graphical Elevation (Polkit Prompts)
When installing packages, mounting internal disks, or altering network settings, Polkit invokes `pam_howdy.so` to authenticate graphical elevation prompts without requiring typed credentials.

### SDDM Boot Login
At the initial graphical display manager after booting, looking into the IR camera logs you directly into your Omarchy Hyprland desktop.

---

## 7. Management UI & Configuration

Access the management interface via:
* **Launcher:** <kbd>Super + Space</kbd> $\rightarrow$ **Setup** $\rightarrow$ **Security** $\rightarrow$ **Face Unlock**
* **Command Line:** `omarchy setup security face`

### Menu Actions

```
  Face Unlock Management
  • Service Status:          Active
  • Enrolled Face Profiles:  4
  • Lockscreen Grace Delay:  4s
  • Recognition Strictness:  3.5
  • Anti-Spoofing IR Guard:  Active (IR Hardware)
  • Intruder Snapshots:      0 recorded
  • Audio Feedback:          on
  • IR Camera Sensor:        /dev/video2

  ➕  Enroll new face profile
  🧠  Adaptive Multi-Condition Calibration Wizard
  📋  List enrolled face profiles
  🗑️   Remove an enrolled face profile
  ⏱️   Configure lockscreen delay
  🎯  Configure recognition sensitivity (certainty)
  🛡️   Configure Anti-Spoofing & Liveness Guard
  📸  View / Manage Intruder Snapshots
  🔒  Toggle Privacy Mode (Enable/Disable)
  🔊  Toggle / Test unlock audio chimes
  🛡️   Configure Polkit & Clamshell PAM rules
  👁️   Test camera feed (live preview)
  🖥️   Preview lock screen animations
  📖  User Manual & Reference Guide
  🚪  Exit
```

* **Privacy Mode:** Instantly toggles `howdy disable 1` / `howdy disable 0` for high-privacy environments without wiping your trained models.
* **Sensitivity Tuning (Certainty):** Adjusts the Euclidean embedding distance threshold:
  - `Strict (2.8)`: Zero tolerance, highest security (requires multiple trained profiles).
  - `Balanced (3.5)`: Recommended default; excellent balance of speed and security.
  - `Lenient (4.2)`: Forgiving in extreme angles; higher tolerance.

---

## 8. Troubleshooting & FAQ

### Camera isn't scanning when locked
1. Check if Panic Lockdown was activated: look for the padlock shield (`󰌾`). If active, enter your master password.
2. Check if the attempt limit was reached: if *"Face scan paused"* is shown, press <kbd>Enter</kbd> to rescan.
3. Verify the IR emitter service is running:
   ```bash
   systemctl status linux-enable-ir-emitter.service
   ```
4. Test the IR camera feed directly:
   ```bash
   sudo howdy test
   ```

### Recognition fails in pitch darkness
Ensure the IR emitter is strobing. If it does not light up with faint red LEDs during scanning, reconfigure the emitter:
```bash
sudo linux-enable-ir-emitter configure -m -g
```

### Master password unlock feels slow
Omarchy's PAM configuration keeps `omarchy-lock-password` completely separate from Howdy. Password verification never waits for the camera; if you experience password lag, verify that `pam_howdy.so` is NOT listed in `/etc/pam.d/omarchy-lock-password`.

---

## 9. Quick Command Reference

```bash
# Open Face Unlock Management UI
omarchy setup security face

# Open this User Manual
omarchy setup security face --manual

# Test IR Camera Video Stream
sudo howdy test

# List Enrolled Face Profiles
sudo howdy list

# Enroll a New Profile
sudo howdy add <label>

# Remove a Profile
sudo howdy remove <id>

# Toggle Face Unlock Privacy Mode
sudo howdy disable 1   # Disable / Pause
sudo howdy disable 0   # Enable / Resume

# Set Lock Grace Delay (seconds)
echo 4 > ~/.config/omarchy/face-unlock-delay

# Toggle Audio Chimes
echo on > ~/.config/omarchy/face-unlock-sound    # Enable
echo off > ~/.config/omarchy/face-unlock-sound   # Disable

# Preview Lock Screen UI Animations
omarchy-shell lock preview

# View Intruder Snapshots
ls -lt ~/.local/state/omarchy/intruder-snapshots/

# Clear Intruder Snapshots
rm -f ~/.local/state/omarchy/intruder-snapshots/*.jpg

# Reload Omarchy Shell
omarchy restart shell
```
