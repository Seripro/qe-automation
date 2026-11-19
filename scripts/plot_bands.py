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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot QE bands.x .gnu data relative to the Fermi energy."
    )
    parser.add_argument("input", type=Path, help="bands.out.gnu file")
    parser.add_argument("--fermi", type=float, required=True, help="Fermi energy in eV")
    parser.add_argument("--output", type=Path, default=Path("bands.png"))
    parser.add_argument("--ymin", type=float, default=-15.0)
    parser.add_argument("--ymax", type=float, default=15.0)
    args = parser.parse_args()

    bands = read_bands(args.input)
    figure, axis = plt.subplots(figsize=(8, 6), constrained_layout=True)
    for band in bands:
        x_values, energies = zip(*band)
        axis.plot(x_values, [energy - args.fermi for energy in energies], color="tab:blue", linewidth=0.8)

    axis.axhline(0.0, color="black", linestyle="--", linewidth=0.8, label="Fermi level")
    axis.set_xlabel("k-path distance")
    axis.set_ylabel(r"Energy - $E_F$ (eV)")
    axis.set_ylim(args.ymin, args.ymax)
    axis.legend(loc="upper right")
    figure.savefig(args.output, dpi=180)


if __name__ == "__main__":
    main()
