#!/usr/bin/env python3
"""Cuts the promo video from the captured takes (capture.sh), the titles
(overlays.js) and a music track, with ffmpeg.

    python3 tools/promo/edit.py timeline.json out.mp4 [--vertical]

timeline.json:
{
  "clips": "/tmp/promo/out", "overlays": "/tmp/promo/ov",
  "music": "track.mp3", "music_from": 60.0, "music_db": -6,
  "segments": [
    {"clip": "f_peb7-1.mp4", "from": 0.3, "dur": 3.2, "game_db": -14,
     "over": ["hook", "chip_peb7"], "duck": false},
    {"devices": {"mac": "f_peb18-1.mp4", ...}, "dur": 3.0, "over": []},
    {"card": "end", "dur": 4.0}
  ]
}

Each segment is cut to the frame, titles fade in and out over it, its game
sound is set to game_db, then the pieces are joined with hard cuts (the end
card fades up from black). The music runs under everything, ducked by 10 dB
where a segment says "duck" (the birdsong), and fades out at the end.
--vertical makes a 1080x1920 cut: the footage across the middle over a
blurred copy of itself, with the vertical titles (name_v.png). Dev tool only.
"""
import json
import os
import subprocess
import sys
import tempfile

FPS = 30


def run(cmd):
    subprocess.run(cmd, check=True)


def overlay_chain(base, overs, dur, start_index):
    """Filter text laying each title over `base`, fading in and out."""
    parts = []
    cur = base
    for k, _ in enumerate(overs):
        idx = start_index + k
        fin = 0.25
        fout = 0.3
        parts.append("[%d:v]format=rgba,fade=t=in:st=0.15:d=%.2f:alpha=1,fade=t=out:st=%.2f:d=%.2f:alpha=1[o%d]"
                     % (idx, fin, max(dur - fout - 0.05, 0.2), fout, k))
        parts.append("[%s][o%d]overlay=0:0:format=auto[b%d]" % (cur, k, k))
        cur = "b%d" % k
    return parts, cur


def render_segment(i, seg, cfg, tmp, vertical):
    W, H = (1080, 1920) if vertical else (1920, 1080)
    dur = seg["dur"]
    out = os.path.join(tmp, "seg%02d.mp4" % i)
    ov_dir = cfg["overlays"]
    suffix = "_v" if vertical else ""
    overs = [os.path.join(ov_dir, o + suffix + ".png") for o in seg.get("over", [])]
    inputs = []
    filters = []
    gain = 10 ** (seg.get("game_db", -12) / 20.0)
    if "card" in seg:
        inputs += ["-loop", "1", "-t", str(dur), "-i", os.path.join(ov_dir, seg["card"] + suffix + ".png")]
        inputs += ["-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=48000:cl=stereo"]
        filters.append("[0:v]format=rgba,scale=%d:%d,fade=t=in:st=0:d=0.6,format=yuv420p[v]" % (W, H))
        audio = "[1:a]anull[a]"
        n_in = 2
    elif "devices" in seg:
        screens = json.load(open(os.path.join(ov_dir, "screens.json")))
        inputs += ["-loop", "1", "-t", str(dur), "-i", os.path.join(ov_dir, "dev_back.png")]
        names = list(seg["devices"].keys())
        for n in names:
            src = seg["devices"][n]
            inputs += ["-ss", str(src.get("from", 0.5)), "-t", str(dur), "-i", os.path.join(cfg["clips"], src["clip"])]
        inputs += ["-loop", "1", "-t", str(dur), "-i", os.path.join(ov_dir, "dev_front.png")]
        filters.append("[0:v]format=rgba[d0]")
        cur = "d0"
        for k, n in enumerate(names):
            x, y, w, h = screens[n]
            filters.append("[%d:v]scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,setpts=PTS-STARTPTS[s%d]" % (k + 1, w, h, w, h, k))
            filters.append("[%s][s%d]overlay=%d:%d[d%d]" % (cur, k, x, y, k + 1))
            cur = "d%d" % (k + 1)
        front = len(names) + 1
        filters.append("[%d:v]format=rgba[fr]" % front)
        filters.append("[%s][fr]overlay=0:0,format=yuv420p,scale=1920:1080[dv]" % cur)
        if vertical:
            # The grid as a square-ish card in the middle of the tall frame.
            filters.append("[dv]split[dva][dvb]")
            filters.append("[dva]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=30:2,eq=brightness=-0.25[bg]")
            filters.append("[dvb]scale=1080:-2[fg]")
            filters.append("[bg][fg]overlay=0:(H-h)/2[v]")
        else:
            filters.append("[dv]null[v]")
        audio = "[1:a]volume=%.3f,aresample=48000[a]" % gain
        n_in = front + 1
    else:
        src = os.path.join(cfg["clips"], seg["clip"])
        inputs += ["-ss", str(seg.get("from", 0.0)), "-t", str(dur), "-i", src]
        speed = seg.get("speed", 1.0)
        sp = "setpts=PTS/%.3f," % speed if speed != 1.0 else ""
        if vertical:
            filters.append("[0:v]%ssplit[va][vb]" % sp)
            filters.append("[va]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=30:2,eq=brightness=-0.22[bg]")
            fg = seg.get("vcrop", 1.0)  # >1 zooms the middle band in
            filters.append("[vb]scale=%d:-2,crop=1080:ih[fg]" % int(1080 * fg))
            filters.append("[bg][fg]overlay=0:(H-h)/2[v0]")
        else:
            filters.append("[0:v]%sscale=1920:1080[v0]" % sp)
        n_in = 1
        audio = "[0:a]volume=%.3f,aresample=48000[a]" % gain
        if speed != 1.0:
            audio = "[0:a]atempo=%.3f,volume=%.3f,aresample=48000[a]" % (speed, gain)
        for o in overs:
            inputs += ["-loop", "1", "-t", str(dur), "-i", o]
        parts, last = overlay_chain("v0", overs, dur, n_in)
        filters += parts
        filters.append("[%s]format=yuv420p[v]" % last)
        overs = []
    if overs:  # titles over a card or the devices
        last_label = "v"
        filters[-1] = filters[-1].replace("[v]", "[vpre]")
        for o in overs:
            inputs += ["-loop", "1", "-t", str(dur), "-i", o]
        parts, last = overlay_chain("vpre", overs, dur, n_in)
        filters += parts
        filters.append("[%s]format=yuv420p[%s]" % (last, last_label))
    filters.append(audio)
    cmd = ["ffmpeg", "-y", "-v", "error"] + inputs + ["-filter_complex", ";".join(filters),
           "-map", "[v]", "-map", "[a]", "-t", str(dur), "-r", str(FPS),
           "-c:v", "libx264", "-preset", "medium", "-crf", "14", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", out]
    run(cmd)
    return out


def main():
    cfg = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    vertical = "--vertical" in sys.argv
    segs = cfg["segments_v"] if vertical and "segments_v" in cfg else cfg["segments"]
    tmp = tempfile.mkdtemp(prefix="promo_edit_")
    pieces = [render_segment(i, s, cfg, tmp, vertical) for i, s in enumerate(segs)]
    lst = os.path.join(tmp, "list.txt")
    with open(lst, "w") as fh:
        for p in pieces:
            fh.write("file '%s'\n" % p)
    joined = os.path.join(tmp, "joined.mp4")
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", joined])
    total = sum(s["dur"] for s in segs)
    # The music: from music_from, ducked under the birdsong, faded out.
    t = 0.0
    ducks = []
    for s in segs:
        if s.get("duck"):
            ducks.append("between(t,%.2f,%.2f)" % (t, t + s["dur"]))
        t += s["dur"]
    duck = "+".join(ducks) if ducks else "0"
    mgain = 10 ** (cfg.get("music_db", -6) / 20.0)
    fade_out = cfg.get("music_fade", 2.5)
    af = ("[1:a]atrim=start=%.3f:duration=%.3f,asetpts=PTS-STARTPTS,aresample=48000,"
          "volume='%.3f*if(%s,0.3,1)':eval=frame,afade=t=in:st=0:d=0.4,afade=t=out:st=%.3f:d=%.2f[m];"
          "[0:a][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]"
          % (cfg.get("music_from", 0.0), total, mgain, duck, max(total - fade_out, 0), fade_out))
    run(["ffmpeg", "-y", "-v", "error", "-i", joined, "-i", cfg["music"], "-filter_complex", af,
         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k",
         "-movflags", "+faststart", out])
    print("%s: %.1f s, %d segments" % (out, total, len(segs)))


if __name__ == "__main__":
    main()
