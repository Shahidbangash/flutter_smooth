import json
import re
from argparse import ArgumentParser
from pathlib import Path
from typing import Callable, List, Dict
from zipfile import ZipFile

TraceEvent = Dict


def synthesize_event(
        *,
        name: str,
        start_us: int,
        tid: int,
        duration_us: int = 10000,
) -> List[TraceEvent]:
    common_args = dict(
        tid=tid,
        name=name,
        cat='synthesized',
        pid=-1000000,
    )

    return [
        dict(ts=start_us, ph='B', **common_args),
        dict(ts=start_us + duration_us, ph='E', **common_args),
    ]


def synthesize_long_event_matching_filter(data, filter_event: Callable[[str], bool], synthesize_tid: int):
    new_events = []
    for e in data['traceEvents']:
        if e['ph'] == 'B' and filter_event(e['name']):
            new_events += synthesize_event(
                name=e['name'],
                start_us=e['ts'],
                tid=synthesize_tid,
            )
    return new_events


def parse_vsync_positions(data) -> List[int]:
    return sorted([
        e['ts'] for e in data['traceEvents']
        if e['ph'] == 'B' and e['name'] == 'VSYNC'
    ])


def parse_raster_end_positions(data) -> List[int]:
    return sorted([
        e['ts'] for e in data['traceEvents']
        if e['ph'] == 'E' and e['name'] == 'GPURasterizer::Draw'
    ])


def synthesize_abnormal_raster_in_interval_events(vsync_positions: List[int], raster_end_positions: List[int]):
    new_events = []
    raster_index = 0
    for vsync_index in range(len(vsync_positions) - 1):
        num_raster_in_vsync_interval = 0
        while raster_index < len(raster_end_positions) and \
                raster_end_positions[raster_index] < vsync_positions[vsync_index + 1]:
            raster_index += 1
            num_raster_in_vsync_interval += 1

        if raster_index >= len(raster_end_positions):
            break

        event_common_args = dict(
            start_us=vsync_positions[vsync_index],
            duration_us=vsync_positions[vsync_index + 1],
            tid=-999999,
        )
        if num_raster_in_vsync_interval == 0:
            new_events += synthesize_event(name='Jank:ZeroRasterEndInVsyncInterval', **event_common_args)
        elif num_raster_in_vsync_interval >= 2:
            new_events += synthesize_event(name='Waste:MultiRasterEndInVsyncInterval', **event_common_args)
    return new_events


def main():
    parser = ArgumentParser()
    parser.add_argument('input')
    args = parser.parse_args()

    path_input = Path(args.input)
    path_output = path_input.parent / f'{path_input.stem}_enhanced.json'

    data = json.loads(path_input.read_text())

    vsync_positions = parse_vsync_positions(data)
    raster_end_positions = parse_raster_end_positions(data)

    data['traceEvents'] += synthesize_abnormal_raster_in_interval_events(vsync_positions, raster_end_positions)

    data['traceEvents'] += synthesize_long_event_matching_filter(
        data, lambda s: re.match(r'.*\.S\.SimpleCounter', s) is not None, synthesize_tid=-999998)

    print(f'#events={len(data["traceEvents"])}')
    path_output.write_text(json.dumps(data))

    with ZipFile(f'{path_input}.zip', 'w') as zipf:
        zipf.write(path_input, arcname=path_input.name)


if __name__ == '__main__':
    main()
