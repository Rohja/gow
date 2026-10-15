# umu-launcher

A generic container to run Windows applications (that don't require Steam) through
[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher), using Proton.

## Configuration

Everything is configured from the app entry in Wolf's `config.toml`:

| What | Where | Description |
|------|-------|-------------|
| Windows app folder | `mounts`: `/host/path:/app:rw` | Host folder containing the application, mounted on `/app` |
| Proton + prefix storage | `mounts`: `umu-launcher:/var/umu:rw` | Volume holding Proton, the Steam Linux Runtime and the wine prefix; kept between runs |
| `UMU_APP_EXE` | env (**required**) | `.exe` to run, relative to `/app` (e.g. `Setup.exe` or `bin/App.exe`) |
| `UMU_PROTON_VERSION` | env, default `GE-Proton` | `GE-Proton` (latest GE-Proton), a release such as `GE-Proton10-4`, `UMU-Latest`, or an absolute path to a Proton folder |
| `UMU_APP_ARGS` | env, optional | Arguments passed to the `.exe`, split on spaces |
| `UMU_GAME_ID` | env, default `umu-default` | umu game id; use `umu-<steam appid>` to apply [protonfixes](https://github.com/Open-Wine-Components/umu-protonfixes) |
| `UMU_APP_WORKDIR` | env, optional | Working directory relative to `/app` (default: the exe's folder) |
| `RUN_GAMESCOPE` / `RUN_SWAY` | env | Compositor used; gamescope by default |

`GE-Proton*` versions are downloaded directly from github.com releases (not the rate-limited GitHub API), using the archive for the container architecture. Only the requested (or latest) version is tried; if its download fails the container exits with an error. On the first launch the requested Proton version and the Steam Linux Runtime are downloaded
automatically into the `umu-launcher` volume, so the container needs internet access and the
first start may take a while. Later launches reuse them.

## Example

```toml
[[apps]]
title = "My Windows app"
start_virtual_compositor = true

[apps.runner]
type = "docker"
name = "WolfMyWindowsApp"
image = "ghcr.io/rohja/umu-launcher:edge"
mounts = [
    "/mnt/games/MyApp:/app:rw",
    "umu-launcher:/var/umu:rw",
]
env = [
    "UMU_PROTON_VERSION=GE-Proton10-4",
    "UMU_APP_EXE=MyApp.exe",
    "UMU_APP_ARGS=-windowed -nointro",
    "RUN_GAMESCOPE=1",
    "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*",
]
# base_create_json: copy it from the default entry
```

Add another `[[apps]]` entry per application; they can share the same `umu-launcher` volume
(Proton is downloaded once) or use separate volumes for separate wine prefixes.
Set `PROTON_LOG=1` in `env` to get a Proton log (written to `$HOME/steam-umu-default.log`).
