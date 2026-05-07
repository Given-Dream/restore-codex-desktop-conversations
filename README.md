# Codex Desktop Conversation Restore

[English](README.md) | [中文](README.zh-CN.md)

This folder contains a Windows helper workflow for restoring local Codex Desktop conversations after switching API/provider with CC Switch.

The main entrypoint is:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat
```

It reads local Codex rollout sessions from `~\.codex\sessions`, lets you choose the original provider, opens CC Switch so you can switch API/provider, then repairs Codex Desktop's local indexes so the selected conversations show up again in the Desktop sidebar.

## What It Does

The PowerShell script updates local Codex Desktop state only:

- Rebuilds `~\.codex\session_index.jsonl`.
- Backfills missing rows in `~\.codex\state_5.sqlite`.
- Marks selected threads visible/unarchived.
- Maps selected threads to the workspace, default `D:\codex`.
- Optionally pins restored threads in Codex Desktop.
- Optionally updates selected rollout metadata to the currently active provider after CC Switch changes it.

It does not upload conversations or sync them to OpenAI/ChatGPT. This is a local repair/visibility workflow.

## Recommended Workflow

1. Run a preview first:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -DryRun
```

2. Check the table. It shows each session's ID, provider, update time, title, and recent-message summary.

3. Run the real restore:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat
```

4. Choose the original API/provider for the conversations you want to restore.

5. CC Switch opens. Switch to the target API/provider.

6. Quit Codex Desktop fully when the script asks. Also quit it from the tray if needed.

7. Press Enter and wait for repair to finish.

8. Reopen Codex Desktop. Restored sessions should appear under `D:\codex`, and usually also in Pinned.

## Common Commands

Preview only:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -DryRun
```

Restore sessions from a specific old provider:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -Provider yuan
```

Restore sessions from all providers:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -AllProviders
```

Use a specific CC Switch executable:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -CcSwitchPath "C:\Users\asus\AppData\Local\Programs\CC Switch\cc-switch.exe"
```

Repair without opening CC Switch:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -NoCcSwitch
```

Keep the original provider in restored session metadata:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -KeepOriginalProvider
```

Do not pin restored threads:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -NoPin
```

Use another workspace root:

```bat
D:\codex\desktop\restore-codex-desktop-conversations.bat -WorkspaceRoot "D:\another-workspace"
```

## Important Options

- `-DryRun`: Shows what would be restored without changing files.
- `-Provider <name>`: Restores only sessions whose original `model_provider` matches this name.
- `-AllProviders`: Restores every local rollout session.
- `-NoCcSwitch`: Skips opening CC Switch.
- `-NoPrompt`: Uses defaults where possible and avoids interactive prompts.
- `-NoWaitForCodexExit`: Does not wait for Codex Desktop to quit. Use carefully, because Desktop may overwrite state while running.
- `-KeepOriginalProvider`: Does not rewrite selected rollout metadata to the new current provider.
- `-NoPin`: Restores visibility but does not add sessions to pinned threads.
- `-IncludeNonInteractive`: Includes non-interactive sessions such as exec/review rollouts when present.
- `-SummaryChars <number>`: Controls summary length in the preview table.

## Backups

Before changing important local files, the script creates timestamped backups next to them, for example:

- `session_index.jsonl.bak_YYYYMMDD_HHMMSS`
- `state_5.sqlite.bak_YYYYMMDD_HHMMSS`
- `.codex-global-state.json.bak_YYYYMMDD_HHMMSS`
- `rollout-....jsonl.bak_YYYYMMDD_HHMMSS`

If something looks wrong, stop using Codex Desktop and restore the latest backup manually.

## Requirements

- Windows PowerShell.
- Codex Desktop local data under `~\.codex`.
- CC Switch installed if you want the script to open it automatically.
- `sqlite3` available in `PATH`, because the script repairs `state_5.sqlite`.

Detected CC Switch path on this machine is usually:

```text
C:\Users\asus\AppData\Local\Programs\CC Switch\cc-switch.exe
```

## Notes

The script uses local rollout files as the source of truth. Subagent IDs are not used as conversation IDs; the restore targets Codex conversation/session IDs from rollout filenames and metadata.

If a conversation still does not appear after repair, run `-DryRun` again and confirm it is selected, then close Codex Desktop fully and rerun without `-NoWaitForCodexExit`.
