# Quick Start

This repo is meant to be your local workspace for Make custom apps.

Use it like this:

1. Clone this repo.
2. Open it in VS Code.
3. Use the Make custom apps VS Code extension from inside this repo.
4. Export apps into the repo `src/` folder.
5. Prepare destination app IDs with the scripts in this folder.
6. Deploy from the VS Code extension.

Loom reference:

- <https://loom.com/share/d493400edde04220923b2d0dc4f6298e>

## Repo Layout

- `src/` contains one folder per exported custom app
- `scripts/` contains helper scripts for destination prep
- `.env` stores destination connection values for the scripts
- `.secrets/` stores API key files referenced by `makecomapp.json`

Typical structure:

```text
oemapps/
  src/
    docusign/
      makecomapp.json
    emporix/
      makecomapp.json
  scripts/
  .env
  .secrets/
```

## Prerequisites

- VS Code installed
- Make custom apps VS Code extension installed
- `bash`, `curl`, and `jq` available locally
- a valid destination Make API key

Your `.env` should contain:

```bash
destination_API_KEY=your-token
destination_Base_URL=https://us1.make.com/api
```

Example file:

- [.env.sample](/Users/o.chekalov/Desktop/oemapps/.env.sample)

## Open The Repo In VS Code

Clone the repo and open the repo root in VS Code:

```bash
git clone <your-repo-url>
cd oemapps
code .
```

The important part is that VS Code is opened on this repo root, not on some random export folder.

## Connect In The Extension

Inside VS Code:

- open the Make custom apps extension
- create a connection to the source instance
- create a connection to the destination instance
- provide the instance URL and API key for each connection

The extension handles source and destination connections.

The local scripts only use the destination values from `.env`.

## Export Apps Into `src/`

When you clone or export a custom app from the extension, use this repo as the local workspace.

Important rule:

- choose the repo `src/` folder as the export target

That way, each app is created inside this repo as:

```text
src/<app-folder>/
```

Example:

```text
src/docusign/
src/emporix/
```

Each exported app folder should contain a `makecomapp.json`.

The folder name matters because the prep scripts derive the destination origin `label` from that folder name.

If you are re-exporting an app:

- remove the old export first if you want a clean folder
- avoid mixing files from different exports in the same app folder

## Prepare The Destination

Run all script commands from the repo root:

```bash
cd /Users/o.chekalov/Desktop/oemapps
```

### 1. Check what already exists on destination

```bash
bash scripts/list_destination_apps.sh
```

This lists destination apps so you can see whether the app already exists.

### 2. Prepare `makecomapp.json` files

Recommended command:

```bash
bash scripts/prepare_to_sync.sh
```

This script:

- reads `.env`
- writes `.secrets/destination_apikey`
- scans all `makecomapp.json` files
- tries to reuse an existing destination app by `appId` or label
- creates a destination app if needed
- appends the destination origin as the last item in `origins`

The destination app does not need to exist in advance.

If needed, run a dry mode without API creation:

```bash
bash scripts/prepare_to_sync.sh --no-api
```

### 3. Optional simpler flow

There is also:

```bash
bash scripts/setup_destination_make_apps.sh
```

Use this only if you want the simpler script and do not need the reuse logic from `prepare_to_sync.sh`.

## What The Script Writes

The scripts update:

- `.secrets/destination_apikey`
- each exported app’s `makecomapp.json`

The destination origin written into `makecomapp.json` looks like:

```json
{
  "label": "Folder Name In Start Case",
  "appId": "remote-app-id-or-empty",
  "baseUrl": "https://us1.make.com/api",
  "appVersion": 1,
  "apikeyFile": "../../.secrets/destination_apikey"
}
```

After running the prep script, review the generated values:

- `appId`
- `baseUrl`
- `appVersion`
- `apikeyFile`

## Deploy From VS Code

Once the exported app files and `makecomapp.json` look correct:

- go back to the VS Code extension
- use the deploy action
- choose the destination connection
- push the local app from this repo to Make

## Recommended Flow

1. Clone this repo.
2. Open the repo in VS Code.
3. Connect source and destination in the extension.
4. Export each app into `src/`.
5. Fill `.env`.
6. Run `bash scripts/list_destination_apps.sh`.
7. Run `bash scripts/prepare_to_sync.sh`.
8. Review `src/*/makecomapp.json`.
9. Deploy from the VS Code extension.
10. Test in the destination Make instance.

## Troubleshooting

If `zsh` says `command not found`:

- run scripts with `bash scripts/<name>.sh`
- or mark them executable and use `./scripts/<name>.sh`

If a script says `.env` is missing:

- run it from the repo root
- confirm [.env](/Users/o.chekalov/Desktop/oemapps/.env) exists

If the API call fails:

- verify `destination_API_KEY`
- verify `destination_Base_URL`
- verify the Make zone such as `us1`, `us2`, `eu1`, or `eu2`

If the wrong destination app was selected:

- compare the generated `appId` with the output of `bash scripts/list_destination_apps.sh`
- correct the `appId` in `makecomapp.json` before deployment

If `jq` is missing:

- install `jq`
- rerun the script
