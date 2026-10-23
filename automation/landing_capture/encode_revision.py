"""Encode a continuous real-UI retake and its responsive landing presentation.

Raw input is a stopped capture.py take. Both chapters preserve one unbroken
source interval at original speed. Only leading setup may be trimmed.
"""
import argparse
import hashlib
import json
from pathlib import Path
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


def scenario_settings(take, chapter, crop, desktop, mobile):
    receipt_path = take / 'scenario-receipt.json'
    if not receipt_path.exists():
        return crop, desktop, mobile, None
    from scenario_contract import contract, digest
    receipt = json.loads(receipt_path.read_text())
    spec = contract(chapter)
    if receipt.get('clip') != chapter or receipt.get('contract') != spec or receipt.get('scenarioSha256') != digest(spec):
        raise ValueError('Take belongs to another or stale shared storyboard')
    if receipt.get('status') != 'recorded-needs-outcome-and-visual-review':
        raise ValueError('Incomplete storyboard capture cannot be encoded as a replay')
    camera = spec['camera']
    if camera['crop'] is None or spec['edit'].get('internalCuts') != 0:
        raise ValueError('This chapter needs its original shared phone/multi-cue composer, not a generic crop')
    expected = (':'.join(map(str, camera['crop'])), ':'.join(map(str, camera['desktop'])), ':'.join(map(str, camera['mobile'])))
    for supplied, locked in zip((crop, desktop, mobile), expected):
        if supplied is not None and supplied != locked:
            raise ValueError('Per-locale camera/export override is forbidden; version the shared storyboard')
    return *expected, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('chapter', choices=['layout-build', 'form-build', 'layout-refine', 'layout-grid', 'ticket-design', 'seat-select', 'check-in', 'orders-overview'])
    parser.add_argument('take', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--start-at', type=float, help='First genuine motion timestamp; trim only leading setup.')
    parser.add_argument('--crop', help='Source crop W:H:X:Y for the actual recorded viewport')
    parser.add_argument('--size', help='Desktop output W:H')
    parser.add_argument('--mobile-size', help='Mobile presentation W:H')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (args.take / 'scenario-receipt.json').exists() and args.start_at is not None:
        parser.error('Shared storyboard captures do not allow per-locale timing trims')
    frames = json.loads((args.take / 'frames.json').read_text())
    cues = json.loads((args.take / 'cues.json').read_text())
    args.crop, args.size, args.mobile_size, receipt = scenario_settings(args.take, args.chapter, args.crop, args.size, args.mobile_size)
    layout = args.chapter.startswith('layout-')
    desktop_size = args.size or ('1140:792' if layout else '1200:822' if args.chapter == 'ticket-design' else '1200:804')
    mobile_size = args.mobile_size or ('820:792' if layout else '900:720' if args.chapter == 'ticket-design' else '720:638')
    start = args.start_at if args.start_at is not None else cues[0]['start']
    if not cues[0]['start'] <= start < cues[-1]['end']:
        parser.error('Motion start must lie inside the recorded action interval')
    spans = [dict(name='unbroken-' + args.chapter, start=start, end=cues[-1]['end'])]
    parts, records = [], []
    for index, cue in enumerate(spans):
        listing = output / f'{args.chapter}-{index}.ffconcat'
        manifest(args.take.resolve(), frames, cue['start'], cue['end'], listing)
        speed = 1
        crop = args.crop or ('1128:780:0:112' if layout else '960:600:200:260' if args.chapter == 'ticket-design' else '1000:760:0:180')
        width,height=map(int,desktop_size.split(':'))
        content_size = receipt['contract']['camera'].get('scaleContent', [width-12, height-12]) if receipt else [width-12,height-12]
        vf = (f'crop={crop},scale={content_size[0]}:{content_size[1]}:force_original_aspect_ratio=decrease:force_divisible_by=2,'
              f'pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,'
              f'setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p')
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
    mobile = output / f'{args.chapter}-mobile.mp4'
    size = mobile_size
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
                 internalCuts=0, speed=1, leadingSetupTrim=start-cues[0]['start'],
                 mobilePresentation='scaled desktop authoring, not native mobile UI')
    if receipt:
        proof['scenarioSha256'] = receipt['scenarioSha256']
        proof['sourceTreeSha256'] = receipt['sourceTreeSha256']
        proof['scenarioStatus'] = 'encoded-needs-paired-locale-and-visual-review'
        receipt['exports']={'desktop':list(map(int,desktop_size.split(':'))),'mobile':list(map(int,mobile_size.split(':')))}
        receipt['exportSha256']={'desktop':hashlib.sha256(desktop.read_bytes()).hexdigest(),'mobile':hashlib.sha256(mobile.read_bytes()).hexdigest()}
        (args.take/'scenario-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    (output / f'{args.chapter}-proof.json').write_text(json.dumps(proof, indent=2))
    print(json.dumps(results))


if __name__ == '__main__':
    main()
