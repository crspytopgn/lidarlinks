#!/usr/bin/env python3
"""A pretend launch monitor for testing OpenLinks without hardware.

It connects to the game the way a real launch monitor app does (GSPro Open
Connect v1: JSON over TCP, port 921), sends heartbeats and shots, and prints
what the game answers. When the game says which club is up (code 201), the
next shot uses typical tour numbers for that club, with a little scatter.

Turn on Settings > Launch monitor in the game first, then:

    python3 tools/openconnect/sim_monitor.py            # Enter hits a shot
    python3 tools/openconnect/sim_monitor.py --shots 5  # five shots, 8 s apart
    python3 tools/openconnect/sim_monitor.py --club 7I --slice
    python3 tools/openconnect/sim_monitor.py --host 192.168.1.20  # game on another PC

Standard library only. See docs/launch-monitors.md.
"""

import argparse
import json
import random
import socket
import sys
import threading
import time

# club: (ball speed mph, launch deg, total spin rpm), roughly PGA Tour averages.
CLUBS = {
    "DR": (167.0, 10.9, 2690), "3W": (158.0, 9.2, 3660), "5W": (152.0, 9.4, 4350),
    "HY": (146.0, 10.2, 4440), "3I": (142.0, 10.4, 4630), "4I": (137.0, 11.0, 4840),
    "5I": (132.0, 12.1, 5360), "6I": (127.0, 14.1, 6230), "7I": (120.0, 16.3, 7100),
    "8I": (115.0, 18.1, 7990), "9I": (109.0, 20.4, 8650), "PW": (102.0, 24.2, 9300),
    "GW": (95.0, 26.0, 9600), "SW": (85.0, 28.0, 9800), "LW": (75.0, 31.0, 9900),
    "PT": (6.0, 2.0, 0), "P": (6.0, 2.0, 0),
}


def shot_message(number, club, rng, shape):
    speed, vla, spin = CLUBS.get(club, CLUBS["7I"])
    putt = club in ("PT", "P")
    axis = {"straight": 0.0, "draw": -6.0, "fade": 6.0, "slice": 18.0, "hook": -18.0}[shape]
    ball = {
        "Speed": round(speed * rng.uniform(0.97, 1.02), 1),
        "VLA": round(vla + rng.uniform(-1.0, 1.0) * (0.5 if putt else 1.5), 1),
        "HLA": round(rng.uniform(-1.0, 1.0) * (1.0 if putt else 2.5), 1),
        "TotalSpin": round(spin * rng.uniform(0.92, 1.08)),
        "SpinAxis": round(0.0 if putt else axis + rng.uniform(-3.0, 3.0), 1),
        "CarryDistance": 0,
    }
    return {
        "DeviceID": "OpenLinks Sim Monitor", "Units": "Yards", "ShotNumber": number,
        "APIversion": "1", "BallData": ball,
        "ClubData": {"Speed": round(ball["Speed"] / 1.48, 1), "AngleOfAttack": 0.0,
                     "FaceToTarget": 0.0, "Path": 0.0},
        "ShotDataOptions": {"ContainsBallData": True, "ContainsClubData": True,
                            "LaunchMonitorIsReady": True, "LaunchMonitorBallDetected": True,
                            "IsHeartBeat": False},
    }


def heartbeat():
    return {"DeviceID": "OpenLinks Sim Monitor", "Units": "Yards", "ShotNumber": 0,
            "APIversion": "1",
            "ShotDataOptions": {"ContainsBallData": False, "ContainsClubData": False,
                                "LaunchMonitorIsReady": True, "IsHeartBeat": True}}


class Link:
    def __init__(self, sock, club):
        self.sock = sock
        self.club = club
        self.lock = threading.Lock()
        self.alive = True

    def send(self, msg):
        with self.lock:
            self.sock.sendall(json.dumps(msg).encode())

    def read_forever(self, fixed_club):
        buf = ""
        dec = json.JSONDecoder()
        while self.alive:
            try:
                data = self.sock.recv(4096)
            except OSError:
                break
            if not data:
                break
            buf += data.decode("utf-8", "replace")
            while buf.strip():
                buf = buf.lstrip()
                try:
                    msg, end = dec.raw_decode(buf)
                except ValueError:
                    break
                buf = buf[end:]
                code = msg.get("Code")
                if code == 201:
                    club = (msg.get("Player") or {}).get("Club", "")
                    if club and not fixed_club:
                        self.club = club
                    print(f"  game: {msg.get('Player')} (club up: {self.club})")
                elif code != 200:
                    print(f"  game: {msg}")
        self.alive = False
        print("  game closed the connection")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=921)
    ap.add_argument("--club", help="always use this club (DR, 7I, PW, PT...)")
    ap.add_argument("--shots", type=int, help="send this many shots, then quit")
    ap.add_argument("--interval", type=float, default=8.0, help="seconds between shots")
    ap.add_argument("--seed", type=int)
    shapes = ["straight", "draw", "fade", "slice", "hook"]
    for s in shapes:
        ap.add_argument("--" + s, dest="shape", action="store_const", const=s)
    ap.set_defaults(shape="straight")
    args = ap.parse_args()
    rng = random.Random(args.seed)

    try:
        sock = socket.create_connection((args.host, args.port), timeout=5)
    except OSError as e:
        sys.exit(f"Can't reach {args.host}:{args.port} ({e}). Is the game running with "
                 "Settings > Launch monitor on?")
    sock.settimeout(None)
    link = Link(sock, (args.club or "DR").upper())
    print(f"Connected to {args.host}:{args.port}")
    threading.Thread(target=link.read_forever, args=(bool(args.club),), daemon=True).start()

    def beats():
        while link.alive:
            time.sleep(5)
            try:
                link.send(heartbeat())
            except OSError:
                link.alive = False

    threading.Thread(target=beats, daemon=True).start()
    time.sleep(0.5)  # let the game say which club is up

    n = 0
    try:
        while link.alive:
            if args.shots is None:
                if input("Enter to hit (q to quit): ").strip().lower() == "q":
                    break
            elif n >= args.shots:
                time.sleep(1.0)
                break
            elif n > 0:
                time.sleep(args.interval)
            if not link.alive:
                break
            n += 1
            msg = shot_message(n, link.club, rng, args.shape)
            b = msg["BallData"]
            print(f"Shot {n} ({link.club}): {b['Speed']} mph, launch {b['VLA']}, "
                  f"HLA {b['HLA']}, {b['TotalSpin']} rpm, axis {b['SpinAxis']}")
            link.send(msg)
    except (KeyboardInterrupt, EOFError):
        pass
    link.alive = False
    sock.close()


if __name__ == "__main__":
    main()
