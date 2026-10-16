**Bar controls (2026-09-23).** Press and hold a thumbnail: macOS's three lights
appear over it (close, minimize, full screen → `.windowCommand` = kind 15, JSON
`WindowCommand`; the host presses the window's own buttons through
Accessibility, using the staged element on the virtual display). Keep holding
and move: the lights go, the thumbnail lifts and drags into a new slot, Home
Screen style; the arrangement is the device's own (`StreamClient.windowOrder`,
persisted per Mac, host order for the rest). A "Leave" button disconnected
(since the host settings step the last slot is Settings, with Disconnect in its
panel's foot). The device asks for the Desktop whenever the host reports nothing
streaming (at most every 10 s), so a fresh connection starts on the Desktop and
the drawer no longer opens by itself. When the watched window has closed it
waits 2 s first, and asks for nothing if the user picked or launched something
meanwhile (the host cannot tell that request from a Desktop tap). Harness:
`-SillWindowMenu 1` keeps the first thumbnail's lights open.
