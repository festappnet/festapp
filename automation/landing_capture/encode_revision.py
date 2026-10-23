"""Encode a continuous real-UI retake and its responsive landing presentation.

Raw input is a stopped capture.py take. Only the layout copy cue is accelerated;
the complete form workflow retains original timing, including scrolling.
"""
import argparse
import json
from pathlib import Path
import sys

import subprocess


def run(command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:])
    return result.stdout


def probe(path):
    data = json.loads(run(['ffprobe', '-v', 'error', '-show_streams',
                           '-show_format', '-of', 'json', str(path)]))
    return data['streams'][0], float(data['format']['duration'])


def quoted(path):
    return str(path).replace("'", "'\\''")


def manifest(take, frames, start, end, target):
    before = [frame for frame in frames if frame['time'] <= start]
    if not before:
        raise ValueError('Missing actual frame at cue start')
    selected = [dict(before[-1], time=start)] + [
        frame for frame in frames if start < frame['time'] < end]
    lines = ['ffconcat version 1.0']
    for index, frame in enumerate(selected):
        stop = selected[index + 1]['time'] if index + 1 < len(selected) else end
        if stop > frame['time']:
            lines += [f"file '{quoted(take / frame['file'])}'", 'option framerate 1000',
                      f"duration {stop - frame['time']:.6f}"]
    lines += [f"file '{quoted(take / selected[-1]['file'])}'", 'option framerate 1000']
    target.write_text('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('chapter', choices=['layout-build', 'form-build'])
    parser.add_argument('take', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    frames = json.loads((args.take / 'frames.json').read_text())
    cues = json.loads((args.take / 'cues.json').read_text())
    layout = args.chapter == 'layout-build'
    spans = cues if layout else [dict(name='continuous-form', start=cues[0]['start'], end=cues[-1]['end'])]
    parts, records = [], []
    for index, cue in enumerate(spans):
        listing = output / f'{args.chapter}-{index}.ffconcat'
        manifest(args.take.resolve(), frames, cue['start'], cue['end'], listing)
        speed = 1.5 if cue['name'] == 'complete-second-row' else 1
        crop = '1128:780:0:112' if layout else '1000:760:0:180'
        vf = (f'crop={crop},scale=in_range=full:out_range=limited,'
              + ('pad=1140:792:6:6:color=0xebf1f6,' if layout else
                 'scale=1176:780:force_original_aspect_ratio=decrease:force_divisible_by=2,'
                 'pad=1200:804:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,')
              + f'setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p')
        part = output / f'{args.chapter}-{index}.mp4'
        run(['ffmpeg', '-v', 'error', '-y', '-safe', '0', '-i', str(listing),
             '-t', str((cue['end'] - cue['start']) / speed), '-vf', vf,
             '-an', '-c:v', 'libx264', '-crf', '20', '-preset', 'fast', str(part)])
        records.append(dict(cue=cue['name'], sourceStart=cue['start'], sourceEnd=cue['end'],
                            speed=speed, encodedDuration=probe(part)[1]))
        parts.append(part)
    listing = output / f'{args.chapter}.ffconcat'
    listing.write_text('\n'.join(f"file '{quoted(part)}'" for part in parts))
    desktop = output / f'{args.chapter}.mp4'
    run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(listing),
         '-c', 'copy', '-movflags', '+faststart', str(desktop)])
    if layout:
        sys.path.insert(0, str(Path(__file__).parent / 'layout'))
        from remove_copy_collision_frames import trim
        cuts = trim(desktop, records, allowed_prefixes=('complete-second-row',))
        (output / 'copy-transition-cuts.json').write_text(json.dumps(cuts, indent=2))
    mobile = output / f'{args.chapter}-mobile.mp4'
    size = '820:792' if layout else '720:638'
    run(['ffmpeg', '-v', 'error', '-y', '-i', str(desktop), '-vf',
         f'scale={size}:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,'
         f'pad={size}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,format=yuv420p',
         '-an', '-c:v', 'libx264', '-crf', '20', '-preset', 'fast', '-movflags', '+faststart', str(mobile)])
    results = {}
    for video in (desktop, mobile):
        run(['ffmpeg', '-v', 'error', '-i', str(video), '-f', 'null', '-'])
        for suffix, time in [('', '-0.2'), ('-start', None)] if layout else [('', '-0.2')]:
            jpg = output / f'{video.stem}{suffix}.jpg'
            seek = ['-sseof', time] if time else []
            run(['ffmpeg', '-v', 'error', '-y', *seek, '-i', str(video), '-frames:v', '1', str(jpg)])
            run(['cwebp', '-quiet', '-q', '92', str(jpg), '-o', str(jpg.with_suffix('.webp'))])
        stream, duration = probe(video)
        results[video.name] = dict(width=stream['width'], height=stream['height'], duration=duration, decode='PASS')
    proof = dict(sourceTake=str(args.take.resolve()), cues=records, outputs=results,
                 mobilePresentation='scaled desktop authoring, not native mobile UI')
    (output / f'{args.chapter}-proof.json').write_text(json.dumps(proof, indent=2))
    print(json.dumps(results))


if __name__ == '__main__':
    main()
