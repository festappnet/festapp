"""Encode real hall growth with an explicit eightfold copy-growth time compression.

Usage: python encode_growth.py TAKE_DIRECTORY --output-dir EXTERNAL_REVIEW_DIRECTORY
This never publishes canonical media. Requires completed frames.json and cues.json.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ORDER = ('empty-hall', 'first-slow-drag', 'copy-growth', 'additional-table',
         'automatic-chairs', 'round-table', 'round-chairs', 'finished-hall')
CONTROL = (1174, 350, 250, 55)
DETAIL_CENTERS = {'automatic-chairs': (695, 285), 'round-chairs': (696, 666)}


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
    # Palette and real pointer remain visible during every drag. Inspector is
    # excluded from the normal view; only the real count/+ strip is inset when
    # the application is adding chairs. Both branches originate in the SAME frame.
    if name in DETAIL_CENTERS:
        cx, cy = DETAIL_CENTERS[name]
        x, y = round(cx - 310), max(114, round(cy - 224))
        graph = (f'[0:v]split=2[scene][control];'
                 f'[scene]crop=620:448:{x}:{y},scale=1140:824:flags=lanczos[detail];'
                 f'[control]crop=250:55:1174:350,scale=600:132:flags=lanczos[strip];'
                 f'[detail][strip]overlay=270:672[composed];')
    else:
        graph = '[0:v]crop=1140:824:0:114[composed];'
    return graph + f'[composed]setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p[out]'


def probe(path):
    value = json.loads(run(['ffprobe', '-v', 'error', '-show_streams', '-show_format',
                            '-of', 'json', str(path)]))
    return value['streams'][0], float(value['format']['duration'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('take', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
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
    for index, name in enumerate(ORDER):
        cue = cues[name]; start, end = cue['start'], cue['end']
        if name == 'empty-hall':
            start = max(start, end - 1.0)
        speed = 8 if name == 'copy-growth' else 1
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
        if (stream['width'], stream['height']) != (1140, 824) or abs(actual - duration) > .07:
            raise RuntimeError(f'Unexpected dimensions/duration in {name}: {actual} vs {duration}')
        records.append(dict(cue=name, sourceStart=start, sourceEnd=end, speed=speed,
                            expectedDuration=duration, encodedDuration=actual,
                            controlInset=CONTROL if name in DETAIL_CENTERS else None,
                            detailCenter=DETAIL_CENTERS.get(name)))
        paths.append(video)
    joined = parts / 'join.ffconcat'
    joined.write_text('\n'.join(f"file '{quoted(path)}'" for path in paths) + '\n')
    desktop = output / 'layout-build.mp4'
    run(['ffmpeg', '-v', 'error', '-y', '-safe', '0', '-f', 'concat', '-i', str(joined),
         '-c', 'copy', '-movflags', '+faststart', str(desktop)])
    mobile = output / 'layout-build-mobile.mp4'
    run(['ffmpeg', '-v', 'error', '-y', '-i', str(desktop), '-vf',
         'scale=820:824:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=820:824:(ow-iw)/2:(oh-ih)/2:color=0xf3f4f6,format=yuv420p',
         '-an', '-c:v', 'libx264', '-crf', '20', '-preset', 'fast', '-movflags', '+faststart', str(mobile)])
    for video, size in [(desktop, (1140, 824)), (mobile, (820, 824))]:
        stream, duration = probe(video)
        if (stream['width'], stream['height']) != size:
            raise RuntimeError('Wrong output dimensions')
        run(['ffmpeg', '-v', 'error', '-i', str(video), '-f', 'null', '-'])
        run(['ffmpeg', '-v', 'error', '-y', '-sseof', '-0.2', '-i', str(video),
             '-frames:v', '1', str(video.with_suffix('.jpg'))])
    evidence = dict(sourceTake=str(take), desktopSize=[1140, 824], mobileSize=[820, 824],
                    mobilePresentation='scaled desktop editorial crop with plain padding; not native mobile UI',
                    copyCompression=8, cues=records)
    (output / 'growth-edit.json').write_text(json.dumps(evidence, indent=2))
    print(f'Encoded {len(records)} real cues; {probe(desktop)[1]:.3f}s; canonical assets untouched')


if __name__ == '__main__':
    main()
