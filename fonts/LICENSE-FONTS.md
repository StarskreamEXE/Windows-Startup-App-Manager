# Bundled font licences

All three families are distributed under the **SIL Open Font License 1.1** (OFL), which
permits bundling and redistribution with software, provided the fonts are not sold on their
own and reserved font names are respected. Full licence text: https://openfontlicense.org

| Family | Files | Copyright | Source |
|---|---|---|---|
| Inter | `Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf` | © The Inter Project Authors (Rasmus Andersson) | https://github.com/rsms/inter |
| JetBrains Mono | `JetBrainsMono-Regular.ttf`, `-Medium.ttf`, `-SemiBold.ttf`, `-Bold.ttf` | © 2020 The JetBrains Mono Project Authors | https://github.com/JetBrains/JetBrainsMono |
| Press Start 2P | `PressStart2P-Regular.ttf` | © 2012 The Press Start 2P Project Authors (CodeMan38) | https://github.com/google/fonts/tree/main/ofl/pressstart2p |

Full upstream copyright notices and license texts are bundled alongside the fonts:

- [Inter](OFL-Inter.txt), from [rsms/inter LICENSE.txt](https://github.com/rsms/inter/blob/master/LICENSE.txt).
- [JetBrains Mono](OFL-JetBrainsMono.txt), from [JetBrains/JetBrainsMono OFL.txt](https://github.com/JetBrains/JetBrainsMono/blob/master/OFL.txt).
- [Press Start 2P](OFL-PressStart2P.txt), from [google/fonts OFL.txt](https://github.com/google/fonts/blob/main/ofl/pressstart2p/OFL.txt).

The font files are unmodified. `Install.ps1` installs these per-user (no admin) only if they are not already present. `-Portable` skips font installation.
