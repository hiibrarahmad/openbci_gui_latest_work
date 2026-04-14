# OpenBCI GUI Work Plan and Changes

## Working Folder
- D:\nuero11\openbci_gui_latest_work

## Goal
- Use this folder as the only workspace for OpenBCI GUI source changes.

## Initial Setup (2026-04-14)
- Created separate folder and cloned latest source from https://github.com/OpenBCI/OpenBCI_GUI
- Configured direct run command using Processing 4 processing-java.exe

## Run Command
- From PowerShell:
  - D:\nuero11\processing-4.2\processing-4.2\processing-java.exe --sketch="D:\nuero11\openbci_gui_latest_work\OpenBCI_GUI" --run
- From Command Prompt (cmd):
  - "D:\nuero11\processing-4.2\processing-4.2\processing-java.exe" --sketch="D:\nuero11\openbci_gui_latest_work\OpenBCI_GUI" --run

## Run Now (Executed)
- Executed command:
  - D:\nuero11\processing-4.2\processing-4.2\processing-java.exe --sketch="D:\nuero11\openbci_gui_latest_work\OpenBCI_GUI" --run
- Current result in this environment:
  - Updated GUI now launches after fixing the Processing duplicate-library conflict.
  - Fix applied: disabled duplicate `jna.jar` and `jna-platform.jar` in global `LSLLink` Processing library.

## Environment Fix Applied
- Global Processing library path:
  - C:\Users\hiibr\OneDrive\ドキュメント\Processing\libraries\LSLLink\library
- Disabled duplicate jars:
  - jna.jar.disabled
  - jna-platform.jar.disabled

## Change Log
- 2026-04-14: Initialized dedicated workspace and tracking file.
- 2026-04-14: Added new startup data source option in OpenBCI GUI: OPEN NEURO11 DEVICE (UDP).
- 2026-04-14: Implemented new UDP board adapter in `OpenBCI_GUI/BoardNeuro11UDP.pde` to ingest 33-byte Cyton-compatible UDP packets and map them to OpenBCI EEG channels.
- 2026-04-14: Wired Neuro11 source into session init flow, control panel rendering, and start-session endpoint validation.
- 2026-04-14: Updated logger/settings handling so Neuro11 mode behaves safely like external streaming mode.

## Next Planned Work
- Verify end-to-end Neuro11 UDP tunnel connection in GUI at 127.0.0.1:12345.
- Perform all future GUI code changes in this folder only.
