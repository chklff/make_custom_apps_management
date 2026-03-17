# Scripts Manual

This folder contains Bash helpers for preparing and inspecting Make app sync data.

## Files In This Folder

### `prepare_to_sync.sh`

Recommended script for real sync preparation.

What it does:

- Reads `destination_API_KEY` and `destination_Base_URL` from the repo root `.env`.
- Writes the destination API key into `.secrets/destination_apikey`.
- Finds every `makecomapp.json` under the repo.
- Fetches existing apps from the destination Make environment.
- For each `makecomapp.json`:
  - skips the file if the destination origin already exists
  - tries to reuse an existing remote app by `appId`
  - otherwise tries to reuse a remote app by label
  - otherwise creates a new remote app
  - appends the destination origin as the last item in `origins`

When to use it:

- Use this first if you want to avoid creating duplicate apps on the destination.

### `list_destination_apps.sh`

Read-only inspection script.

What it does:

- Reads destination credentials from `.env`.
- Calls the destination Make API with pagination.
- Prints every app name, label, and version.
- Prints the total number of apps found.

When to use it:

- Use this before sync to see what already exists on the destination.

## Requirements

- Run commands from the repo root folder
- Bash available on the machine
- `curl` installed
- `jq` installed
- A valid `.env` file in the repo root

Expected `.env` values:

```bash
destination_API_KEY=your-token
destination_Base_URL=https://us1.make.com/api
```

There is also an example file at .env.sample 

## How To Run

Run from the repo root:


### 1. Inspect destination apps

```bash
bash scripts/list_destination_apps.sh
```

Use this to verify connectivity and see whether apps already exist.

### 2. Prepare sync safely

```bash
bash scripts/prepare_to_sync.sh
```

This is the safer default because it reuses destination apps when possible.

Dry mode without API creation:

```bash
bash scripts/prepare_to_sync.sh --no-api
```

In `--no-api` mode, the script still writes the destination origin, but leaves:

- `appId` as an empty string
- `appVersion` as `1`


## What Gets Written

Scripts create or update:

- `.secrets/destination_apikey`
- every discovered `makecomapp.json`

The destination origin written into each `makecomapp.json` looks like:

```json
{
  "label": "Folder Name In Start Case",
  "appId": "remote-app-id-or-empty",
  "baseUrl": "https://us1.make.com/api",
  "appVersion": 1,
  "apikeyFile": "../../.secrets/destination_apikey"
}
```

The exact `apikeyFile` path is calculated relative to the folder containing that `makecomapp.json`.

## Recommended Order

1. Check `.env`
2. Run `bash scripts/list_destination_apps.sh`
3. Run `bash scripts/prepare_to_sync.sh`
4. Inspect updated `src/*/makecomapp.json` files

## Troubleshooting

If a script says `.env` is missing:

- run it from the repo root
- confirm `.env` exists

If `zsh` says `command not found`:

- run the script with `bash scripts/<name>.sh`
- or mark it executable and run it as `./scripts/<name>.sh`

If the API call fails:

- verify `destination_API_KEY`
- verify `destination_Base_URL`
- verify the Make zone in the URL such as `us1`, `eu1`, or `eu2`

If `jq` is missing:

- install `jq` first, then rerun the script

## Short Guidance

- Prefer `prepare_to_sync.sh` for normal use.
- Use `list_destination_apps.sh` to inspect the destination first.
- Use `setup_destination_make_apps.sh` only when you want the simpler direct-create behavior.
