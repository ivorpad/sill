# Standing rules

Rules that hold in every session. Each names the file that has the reasons.

## The hardware encoder is shared

- While Noah streams (a device connected to Sill.app), do not run `simctl io recordVideo`,
  SillHost streams, ReelRenderer or encoder benchmarks. The Mac has one encode engine: the
  Simulator's recorder runs at priority 80 and outranks Sill, and the Claude app's iOS Simulator
  panel (`claude-ios-sim`, priority 60) cut Noah's Retina Desktop from 57 to 33–36 fps.
  (`docs/history/2026-09-24-encoder-busy-not-stuck.md`)
- Run a hardware encoder test only while `Scripts/encoder-check/no-device.sh` passes, before,
  during and after it. Test hosts take `SILL_TEST_SOFTWARE_ENCODER=1` unless the test is the
  hardware. (`docs/agents/build-and-run.md`)

## Test hosts never act on this Mac or the outside world

- Input goes only to `--synthetic` hosts, which post nothing (`in.dry`). `-SillInputScript`,
  `-SillInputTest` and `sillclient.py`'s input and gesture flags against Sill.app or SillHost
  without `--synthetic` post real clicks and keys on this Mac.
- Menus are pressed only on `Scripts/menufixture.swift` (`SILL_TEST_MENU_PID`). A real app's
  menus are read only with `--menu-selftest=TextEdit`, never a bare `--menu-selftest` (the
  frontmost app).
- Never let a test binary take a connection from another machine (the Application Firewall
  prompts): `SILL_TEST_LOOPBACK=1` keeps a test host on 127.0.0.1.
- Never run a test against GitHub: the update check's tests use `Scripts/sillfeed.py`.
- Never touch the login keychain or Sill's real keychain items in a test: throwaway keychains,
  `SILL_TEST_REMOTE_DIR` and test service names only. (`docs/history/2026-09-27-keychain-hardening.md`)
- The bare `SillMenuBar` binary keeps its defaults in the `SillMenuBar` domain: delete it after.

## AWDL and latency

- Keep AWDL-on tests under 20 s and on test service types (`SILL_TEST_SERVICE_TYPE=_silltest._tcp`),
  never `_sill._tcp`. (`docs/agents/build-and-run.md`)
- Never measure latency with a simulator sitting on the connect screen: its nearby search runs in
  the Mac's mDNSResponder and turns the Mac's AWDL on. (`docs/history/2026-09-24-direct-wireless.md`)

## Simulators

- Use a private simulator for live runs and delete it after. The shared ones (the iPad Pro 13")
  hold other work's builds, and installing over them replaces someone else's app.
  (`docs/history/2026-09-24-remote-access.md`)
