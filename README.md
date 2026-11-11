<p align="center"><img src="assets/quadro.png" alt="Quadro" width="200"></p>

# Quadro

UI toolkit plugin for Roblox Studio. Select GUI objects and transform, convert, lay out, style and reuse them from one panel.

## Features

- **Tools**: transform, anchor point, Offset ↔ Scale conversion, text, stroke, corner, padding, text fit and responsive helpers.
- **Effects Lab**: gradient library and editor, stroke & glow, shadow, motion, text mask and 9-slice.
- **Layout**: align, organize, match sizes and restructure siblings.
- **Builders**: paths, draggable panels (`UIDragDetector`) and paged containers.
- **Library**: save colors, sizes, fonts and gradients as tokens, save components, and move the library between places as a file.
- English and Portuguese interface.

## Build from source

Requires [Aftman](https://github.com/LPGhatguy/aftman).

```
aftman install
wally install
rojo build default.project.json --plugin Quadro.rbxm
```

The last command writes `Quadro.rbxm` to your local Studio plugins folder. Studio does not reload a rebuilt local plugin: reopen the place to load it.

## Tests

```
lune run tests/run
selene src
```

## License

[MIT](LICENSE)
