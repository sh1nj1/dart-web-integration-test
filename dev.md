# Developer Notes

## Flutter Web Chrome Debug Failure
- Symptom: `flutter run -d chrome` hangs during "Waiting for connection" and fails with `SocketException: Connection refused`.
- Root cause: Corrupted Chrome profile cached at `.dart_tool/chrome-device/` for this project.
- Fix: Delete `.dart_tool/chrome-device` and rerun the command. Flutter rebuilds the profile automatically and the Chrome debugger attaches normally.

## Docker
- There's no linux arm64 binary for chrome so you can not use arm based machine to run docker.
- If you use mac with aarch64, the docker image won't work.
