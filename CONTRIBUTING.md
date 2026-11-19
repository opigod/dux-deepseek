# Contributing

Issues and pull requests are welcome.

## Development

1. Clone the repository into `~/.config/dms/plugins/DeepSeek` (or symlink the
   checkout there).
2. Enable **DeepSeek** in Settings → Plugins and add the widget to a bar.
3. Reload QML changes with:

   ```bash
   dms ipc call plugins reload deepseek
   ```

4. A full `dms restart` is required after changing a file in `lib/` or adding a
   new QML file. Qt caches imported QML JavaScript modules and directory file
   lists; a plugin reload alone does not pick those up.

5. Run the checks before sending a change:

   ```bash
   bun test
   for f in *.qml; do qmllint -s "$f"; done
   ```

The tested baseline is Dux/DMS 2.1.2; the manifest requires 2.1.0 or newer.

## Rules

- Keep the runtime dependency-free: no Python, Electron, Playwright, curl or jq,
  and no spawned helper processes. Use QML/JS and Qt `XMLHttpRequest`.
- The official API key is authoritative for balance. Do not let the platform
  summary replace an official balance or change its currency.
- Platform costs use the platform wallet currency. Balance history and trends
  use the balance currency. Never format one with the other.
- Keep the zero-balance rule in `lib/parse.js`. The official endpoint can return
  multiple wallets in varying order; a zero-balance wallet must not win over a
  positive one.
- Never commit `plugin_settings.json`, the state file under
  `~/.local/state/dms/plugins/`, API keys, platform tokens or cookies.
- Update `README.md` and the settings table when adding or changing a setting.

## Registry

The Dux plugin registry entry lives in
[`duxlabs-dev/dux-plugin-registry`](https://github.com/duxlabs-dev/dux-plugin-registry).
Follow that repository's `CONTRIBUTING.md` for submissions, including its rules
on plugin overlap, PR descriptions and AI assistance. Do not change the
registry guide from this repository.
