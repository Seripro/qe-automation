#!/usr/bin/env python3
"""QE bands.x が出力した .gnu データをフェルミ準位基準で描画する。"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt


def read_bands(path: Path) -> list[list[tuple[float, float]]]:
    """空行で区切られた各バンドを読み取る。"""
    bands: list[list[tuple[float, float]]] = []
    current: list[tuple[float, float]] = []

    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            if current:
                bands.append(current)
                current = []
            continue
        if len(fields) < 2:
            raise ValueError(f"Unexpected line in {path}: {line!r}")
        current.append((float(fields[0]), float(fields[1])))

    if current:
        bands.append(current)

    if not bands:
        raise ValueError(f"No band data was found in {path}")
    return bands


def read_kpath(path: Path) -> list[tuple[str, int]]:
    """kp.pwscf のコメントから高対称点ラベルと区間点数を読み取る。"""
    lines = path.read_text().splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip().upper().startswith("K_POINTS"))
        count = int(lines[start + 1].strip())
    except (StopIteration, IndexError, ValueError) as error:
        raise ValueError(f"Could not read K_POINTS {{crystal_b}} from {path}") from error

    points: list[tuple[str, int]] = []
    for line in lines[start + 2 : start + 2 + count]:
        values, _, comment = line.partition("!")
        fields = values.split()
        if len(fields) < 4:
            raise ValueError(f"Unexpected k-point line in {path}: {line!r}")
        label = comment.strip() or "?"
        points.append((label, int(fields[3])))
    return points


def kpath_ticks(kpath: list[tuple[str, int]], x_values: tuple[float, ...]) -> list[tuple[float, str]]:
    """crystal_bの区間点数を使い、bands.out.gnuの横軸上に高対称点を置く。"""
    if not kpath:
        return []

    ticks: list[tuple[float, str]] = [(x_values[0], kpath[0][0])]
    point_index = 0
    for (_, segment_points), (next_label, _) in zip(kpath, kpath[1:]):
        # crystal_bでは、現在の点の4列目が次の点までの分割数。
        # 0は経路の不連続点で、次の点を1つ進めて表示する。
        point_index += segment_points if segment_points > 0 else 1
        point_index = min(point_index, len(x_values) - 1)
        ticks.append((x_values[point_index], next_label))

    merged: list[tuple[float, str]] = []
    for position, label in ticks:
        if merged and abs(position - merged[-1][0]) < 1e-9:
            merged[-1] = (position, f"{merged[-1][1]} | {label}")
        else:
            merged.append((position, label))
    return merged


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot QE bands.x .gnu data relative to the Fermi energy."
    )
    parser.add_argument("input", type=Path, help="bands.out.gnu file")
    parser.add_argument("--fermi", type=float, required=True, help="Fermi energy in eV")
    parser.add_argument("--output", type=Path, default=Path("bands.png"))
    parser.add_argument("--kpath", type=Path, help="kp.pwscf file for high-symmetry labels")
    parser.add_argument("--ymin", type=float, default=-15.0)
    parser.add_argument("--ymax", type=float, default=15.0)
    args = parser.parse_args()

    bands = read_bands(args.input)
    figure, axis = plt.subplots(figsize=(8, 6), constrained_layout=True)
    for band in bands:
        x_values, energies = zip(*band)
        axis.plot(x_values, [energy - args.fermi for energy in energies], color="tab:blue", linewidth=0.8)

    axis.axhline(0.0, color="black", linestyle="--", linewidth=0.8, label="Fermi level")
    if args.kpath:
        ticks = kpath_ticks(read_kpath(args.kpath), tuple(value[0] for value in bands[0]))
        positions, labels = zip(*ticks)
        axis.set_xticks(positions, labels)
        for position in positions:
            axis.axvline(position, color="0.8", linewidth=0.6, zorder=0)
    axis.set_xlabel("k-path distance")
    axis.set_ylabel(r"Energy - $E_F$ (eV)")
    axis.set_ylim(args.ymin, args.ymax)
    axis.legend(loc="upper right")
    figure.savefig(args.output, dpi=180)


if __name__ == "__main__":
    main()
