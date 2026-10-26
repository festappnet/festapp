"""Encode real branded hall growth with cropped object palette and canvas only.

Usage: python encode_brand.py TAKE_DIRECTORY --output-dir EXTERNAL_REVIEW_DIRECTORY
This never publishes canonical media. Requires completed frames.json and cues.json.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ORDER = ('empty-hall','first-slow-drag','copy-row-1','copy-row-2','copy-row-3','copy-bottom','arc-insert','arc-adjust','arc-move','finished-hall')
PALETTE = (0, 410, 232, 510)
CANVAS = (338, 168, 715, 715)


def run(command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-5000:])
    return result.stdout


def quoted(path):
    return str(path).replace("'", "'\\''")


def manifest(take, frames, start, end, target):
    before = [frame for frame in frames if frame['time'] <= start]
    if not before:
        raise ValueError('No actual frame exists at cue start')
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


def composition(name, speed):
    # Keep original x/y relationships including the native drag-feedback corridor.
    # Full left palette remains visible; no masks or replacement pixels.
    # Never synthesize a dragged node.
    return ('[0:v]crop=1128:780:0:112,scale=in_range=full:out_range=limited,format=yuv420p,'
            'pad=1140:792:6:6:color=0xebf1f6,'
            f'setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p[out]')


def probe(path):
    value = json.loads(run(['ffprobe', '-v', 'error', '-show_streams', '-show_format',
                            '-of', 'json', str(path)]))
    return value['streams'][0], float(value['format']['duration'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('take', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--start-at-first-drag', action='store_true', help='Omit the initial empty-hall hold; start at the genuine first table drag.')
    args = parser.parse_args()
    take, output = args.take.resolve(), args.output_dir.resolve()
    if not (take / 'frames.json').is_file() or not (take / 'cues.json').is_file():
        parser.error('Take must be explicitly stopped with complete frames.json and cues.json')
    if output == take:
        parser.error('Keep encoded output separate from raw take')
    output.mkdir(parents=True, exist_ok=True)
    parts = output / 'parts'; parts.mkdir(exist_ok=True)
    frames = json.loads((take / 'frames.json').read_text())
    cues = {cue['name']: cue for cue in json.loads((take / 'cues.json').read_text())}
    if any(name not in cues for name in ORDER):
        parser.error('Required action cue missing')
    records, paths = [], []
    for index, name in enumerate(n for n in ORDER if not (args.start_at_first_drag and n == 'empty-hall')):
        cue = cues[name]; start, end = cue['start'], cue['end']
        # Remove only the last 0.8s of recorded idle hold; preserve native motion.
        if name != 'finished-hall':
            end = max(start + .2, end - .8)
        if name == 'empty-hall':
            start = max(start, end - 1.0)
        speed = {'copy-row-1':2,'copy-row-2':4,'copy-row-3':8,'copy-bottom':6,'arc-insert':1.35,'arc-adjust':1.35,'arc-move':1.35}.get(name,1)
        duration = (end - start) / speed
        if duration <= 0:
            raise ValueError(f'Invalid cue span: {name}')
        source_list = parts / f'{index:02d}-{name}.ffconcat'
        manifest(take, frames, start, end, source_list)
        video = parts / f'{index:02d}-{name}.mp4'
        graph = composition(name, speed)
        fingerprint = hashlib.sha256((source_list.read_text() + graph).encode()).hexdigest()
        cache = video.with_suffix('.sha256')
        if not video.exists() or not cache.exists() or cache.read_text() != fingerprint:
            run(['ffmpeg', '-v', 'error', '-y', '-safe', '0', '-i', str(source_list),
                 '-filter_complex', graph, '-map', '[out]', '-t', str(duration), '-an',
                 '-c:v', 'libx264', '-crf', '20', '-preset', 'fast', '-movflags', '+faststart', str(video)])
            cache.write_text(fingerprint)
        stream, actual = probe(video)
        if (stream['width'], stream['height']) != (1140, 792) or abs(actual - duration) > .07:
            raise RuntimeError(f'Unexpected dimensions/duration in {name}: {actual} vs {duration}')
        records.append(dict(cue=name, sourceStart=start, sourceEnd=end, speed=speed,
                            expectedDuration=duration, encodedDuration=actual,
                            paletteCrop=PALETTE, canvasCrop=CANVAS, controlInset=None))
        paths.append(video)
    joined = parts / 'join.ffconcat'
    joined.write_text('\n'.join(f"file '{quoted(path)}'" for path in paths) + '\n')
    desktop = output / 'layout-build.mp4'
    run(['ffmpeg', '-v', 'error', '-y', '-safe', '0', '-f', 'concat', '-i', str(joined),
         '-c', 'copy', '-movflags', '+faststart', str(desktop)])
    from remove_copy_collision_frames import trim
    cuts=trim(desktop,records)
    (output/'copy-transition-cuts.json').write_text(json.dumps(cuts,indent=2))
    mobile = output / 'layout-build-mobile.mp4'
    run(['ffmpeg', '-v', 'error', '-y', '-i', str(desktop), '-vf',
         'scale=820:792:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=820:792:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,format=yuv420p',
         '-an', '-c:v', 'libx264', '-crf', '20', '-preset', 'fast', '-movflags', '+faststart', str(mobile)])
    for video, size in [(desktop, (1140, 792)), (mobile, (820, 792))]:
        stream, duration = probe(video)
        if (stream['width'], stream['height']) != size:
            raise RuntimeError('Wrong output dimensions')
        run(['ffmpeg', '-v', 'error', '-i', str(video), '-f', 'null', '-'])
        run(['ffmpeg', '-v', 'error', '-y', '-sseof', '-0.2', '-i', str(video),
             '-frames:v', '1', str(video.with_suffix('.jpg'))])
    evidence = dict(startAtFirstDrag=args.start_at_first_drag, sourceTake=str(take), desktopSize=[1140, 792], mobileSize=[820, 792],
                    mobilePresentation='scaled desktop editorial crop with plain padding; not native mobile UI',
                    copyCompression=[2,4,8,6], paletteCrop=PALETTE, canvasCrop=CANVAS,
                    composition='continuous source1128x780@0,112; complete palette without masks; padding6,6; no missing drag corridor',
                    cues=records)
    (output / 'brand-edit.json').write_text(json.dumps(evidence, indent=2))
    print(f'Encoded {len(records)} real cues; {probe(desktop)[1]:.3f}s; canonical assets untouched')


if __name__ == '__main__':
    main()
