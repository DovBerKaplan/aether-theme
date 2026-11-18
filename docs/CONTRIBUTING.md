# Contributing

## Development loop

```bash
make components                   # build the five apps (in components/*/build)
make theme                        # regenerate the theme into theme/generated/
```

Run a component **from the source tree** (it then loads QML from `components/*/qml` and the shared module from `components/shared`, so QML edits need only a restart, no rebuild):

```bash
systemctl --user stop aether-island
components/island/build/aether-island        # Ctrl+C to quit
```

Drive it without a mouse: `qdbus6 org.aether.Island /Island org.aether.Island.Expand` (or `Peek`, `Hide`, `Toggle`).

## Testing the UI

The only automated test is the console's split model (`components/console/tests/split-model.test.js`, run by `make check`); the UI itself is tested by hand:

1. `tools/pointer-test.py move 960 1 --hold 4` moves a virtual pointer to the top edge (needs write access to `/dev/uinput`); `click X Y --via-top 0.7` arrives through the edge the way a hand does.
2. Take a screenshot (`spectacle -b -n -f -o /tmp/x.png`) *while the script is still holding*: when it exits, the virtual device vanishes and the island sees "pointer left".
3. Check both color schemes and light/dark wallpapers.

For notifications: `notify-send -a Messages -i mail-message-new "Title" "Body"`, and `-u critical` for urgent ones.

## Conventions

- Files stay under about 500 lines; split by responsibility, not by layer.
- The theme is generated: change the generator, never the output in `theme/generated/`.
- Keep generators deterministic.
- Anything that changes user configuration must be reversible and covered by `install/backup.sh`.
- Do not read from `~/.config` in generators; vendor what you need under `theme/vendor/` with its license.
- QML: no `required property` that repeats a property of the delegate's base type (it shadows it and leaves labels empty). Use `model.role`.
- C++: Qt 6, C++20. Put QML-visible state in small `QObject`s; no business logic in QML beyond layout and animation.

## Known pitfalls

- `Item.top` and other built-in names cannot be redeclared as properties; QML reports "Cannot override FINAL property".
- KWin blur needs a region in window coordinates; if the window is resized, send the region again.
- A layer-shell window's size changes asynchronously; keep the window large while animating and shrink it afterwards.

## Pull requests

Describe what changed on screen, include a screenshot of the affected state (bar, large, toast), and say which checks you ran.
