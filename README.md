# Secondhand 3D

The one-dollar cartridge from the yard sale, now in 3D.

Walk around Millbrook, clear the Hollow, and bring the bell pieces back to the dock. Save file 1 still belongs to Wren. The longer you play, the more the game knows about you, and the statue in the square only moves when you aren't looking at it.

- Play in your browser: https://buggygamesyt.github.io/secondhand3d/
- Android: grab `Secondhand3D.apk` from the latest release. From v1.1 the Android app is a native build (no browser inside), so it runs on phones whose browser 3D crashes.
  - From v1.2 there are two builds of the same app (they install over each other): `Secondhand3D-gl.apk` (OpenGL ES, the default `Secondhand3D.apk`) and `Secondhand3D-vk.apk` (Vulkan). If one shows a black screen on your phone, try the other.
  - Black screen or glitches? Turn on **Safe graphics** on the file screen or in the pause menu. Hold SELECT for a second (or tap with three fingers) to open the info overlay, then tap **Copy log** and paste it in a bug report.

Controls: WASD / arrows walk, mouse or Q/E turn the camera, J/Z = A (talk, open; hold to run), K/X/Space = B (sword; hold then let go to spin), Enter/Esc = START (pause), Tab/M = SELECT (map). Phone: left thumb moves, drag on the right to look, A and B buttons, START and SELECT at the top. Controllers work too.

All story, characters, art, and music are original. The browser version uses three.js under its MIT license (see the header in `web/three.module.min.js`). The Android version in `godot/` runs on Godot Engine 4.5, used under its MIT license (Copyright (c) 2014-present Godot Engine contributors, Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur).

© 2026 Buggy Games YT. All rights reserved. See LICENSE.
