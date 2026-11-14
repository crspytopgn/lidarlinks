# Launch monitors

OpenLinks takes real shots from home launch monitors over **GSPro Open
Connect v1**, the open protocol most home simulators use: the launch monitor
app (or a connector app) opens a TCP connection to port **921** and sends one
JSON message per shot. The game reads the ball data (ball speed, vertical
and horizontal launch angle, total spin and spin axis, or back and side
spin), answers each message with code 200, and tells the app which club is
up (code 201, `"Club": "DR"`, `"7I"`, `"PT"`), so apps that switch to putting
mode on `PT` do so. Club data is accepted but not used yet.

The measured launch replaces the swing meter for that shot. Everything after
launch is the game's own: wind, flight, and the bounce and roll of the
current shot model (Links 2003's own when game files are loaded), with rough
and sand taking off speed and spin as for a swing. Shots are kept as
measured in the round record, so replays play them back.

Desktop builds only (Windows, macOS, Linux). A browser can't listen on a
port, so the web build can't take launch monitor shots.

## Turning it on

1. Settings > Launch monitor > **On (OpenConnect, port 921)**.
2. Start the launch monitor's own app or connector and pick its **GSPro**
   (or "GSPro Connect", "Open Connect", "OpenAPI") output.
3. Point it at this computer: `127.0.0.1` and port `921` when it runs on the
   same PC, or this PC's local IP address (for example `192.168.1.20`) when
   it runs on another device such as a phone or tablet. Allow the game
   through the firewall the first time it asks.
4. The game says "Launch monitor connected." Hit a shot when it's your turn
   to aim.

Close GSPro (and its GSPConnect window) and any other simulator first: only
one program can listen on port 921. If the port is taken, the game says so.

## Brands

"Direct" means the maker's own software has a GSPro or Open Connect output
that can be aimed at our port. "Bridge" means a free third-party program sits
between the device and the game. A `*` in Fairway's list usually means the
maker charges a subscription for simulator output. None of these has been
tried with real hardware yet; please report what works.

| Launch monitor | How it connects | Notes |
| --- | --- | --- |
| Uneekor (EYE XO, EYE XO2, QED, EYE MINI) | Direct: Uneekor's software, GSPro connection | Needs the Uneekor app's simulator output (subscription on some models). Same PC, `127.0.0.1:921`. |
| FlightScope (Mevo+, Mevo Gen 2, X3) | Direct: FS Golf PC app, GSPro / OpenAPI connection; or the MLM2PRO-GSPro-Connector bridge, which also supports Mevo+ | Mevo+ may need the Pro Package for simulator output. |
| Foresight / Bushnell (GC3, GCQuad, QuadMAX, Launch Pro) | Bridge: the GSPro connector for Foresight (FSX 2020 / FSX Play API) | Launch Pro needs a Foresight subscription for simulator output. The connector expects GSPro on the same PC, so run the game there. |
| Full Swing KIT | Direct: Full Swing's GSPro support | Works with GSPro since 2024; pick GSPro in the KIT software. |
| Garmin Approach R10 | Bridge: an R10 connector such as Fairway Bridge or gspro-garmin (kenjdavidson/gspro-connector) | In the Garmin Golf app choose **E6 Connect** under other simulators and enter the bridge's IP and port; the bridge forwards to port 921. |
| Garmin Approach R50 | Direct over Wi-Fi: the R50's GSPro output | Garmin lists GSPro as supported; the R50 and the PC must be on the same network. |
| Rapsodo MLM2Pro | Bridge: MLM2PRO-GSPro-Connector (springbok), or Rapsodo's own GSPro connection | Needs Rapsodo's Premium membership for simulator output. |
| ProTee VX | Direct: ProTee Labs software, GSPro output | Same PC, `127.0.0.1:921`. |
| GolfTrak | Direct if its app offers a GSPro / OpenAPI output | Not checked. |
| Nova (Open Launch) | Direct: the Nova app's GSPro / OpenAPI output | Enter this PC's IP and port 921. |
| GOLFJOY | Direct: GOLFJOY's GSPro integration | GOLFJOY's own guide says no adapter is needed for GSPro. |
| VTrack | Direct if its app offers a GSPro / OpenAPI output | Not checked. |
| Square Golf | Direct: the Square Golf PC app's GSPro connection | Same PC, `127.0.0.1:921`. |
| RAINMAKER by BlueTees | Direct if its app offers a GSPro / OpenAPI output | Not checked. |
| GolfIn Idra, NVisage, other OpenAPI devices | Direct: OpenAPI is the same protocol | Enter this PC's IP and port 921. |
| Others | If a device works with GSPro through a connector that lets you set the IP and port, it should work here. | |

Some makers' GSPro integration talks to GSPro itself rather than to port 921.
Those won't reach OpenLinks without a bridge; tell us which ones and we'll
list a bridge.

## Testing without a launch monitor

`tools/openconnect/sim_monitor.py` pretends to be a launch monitor app. With
the game running and Settings > Launch monitor on:

```bash
python3 tools/openconnect/sim_monitor.py               # Enter hits a shot
python3 tools/openconnect/sim_monitor.py --shots 5     # five shots, 8 s apart
python3 tools/openconnect/sim_monitor.py --club 7I --slice
python3 tools/openconnect/sim_monitor.py --host 192.168.1.20   # game on another PC
```

It sends heartbeats every 5 seconds, follows the club the game says is up
(typical tour numbers for that club, with some scatter), and prints what the
game answers. Shapes: `--draw`, `--fade`, `--hook`, `--slice`. It needs only
Python 3.

The GDScript tests (`_test_launch_monitor_input` in `game/tests/run_tests.gd`)
cover message splitting, heartbeats, back and side spin, the flight
direction, a real socket round trip, and replaying a round played with
measured shots.

## Protocol notes

- TCP, no authentication, port 921 on all of this PC's addresses.
- Messages may arrive back to back or split across reads; the game splits
  them by matching braces.
- Speed is in mph, spin in rpm, angles in degrees. HLA and spin axis are
  positive to the right (a positive axis curves the ball right).
- Heartbeats (`IsHeartBeat: true`) and messages without ball data are
  answered but not played. A ball speed under 1 mph is ignored.
- Code (`OpenConnect`, `OpenConnectServer`) is in `game/scripts/practice/`.
