#!/usr/bin/env python3
"""QEの全DOS・元素／軌道別PDOSをフェルミ準位基準で描画する。"""

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def load_dos(path: Path) -> tuple[np.ndarray, np.ndarray]:
    data = np.loadtxt(path)
    if data.ndim != 2 or data.shape[1] < 2:
        raise ValueError(f"Expected at least two columns in {path}")
    return data[:, 0], data[:, 1]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plot QE total DOS and selected PDOS relative to the Fermi energy."
    )
    parser.add_argument("total_dos", type=Path, help="aiida.pdos_tot file")
    parser.add_argument("--fermi", type=float, required=True, help="Fermi energy in eV")
    parser.add_argument("--component", action="append", default=[], type=Path)
    parser.add_argument("--output", type=Path, default=Path("pdos.png"))
    parser.add_argument("--xmin", type=float, default=-15.0)
    parser.add_argument("--xmax", type=float, default=15.0)
    args = parser.parse_args()

    energies, total_dos = load_dos(args.total_dos)
    figure, axis = plt.subplots(figsize=(8, 6), constrained_layout=True)
    axis.plot(energies - args.fermi, total_dos, color="black", linewidth=1.2, label="Total DOS")

    for component in args.component:
        component_energies, component_dos = load_dos(component)
        label = component.stem.removeprefix("pdos_").replace("_", " ")
        axis.plot(component_energies - args.fermi, component_dos, linewidth=1.0, label=label)

    axis.axvline(0.0, color="black", linestyle="--", linewidth=0.8, label="Fermi level")
    axis.set_xlabel(r"Energy - $E_F$ (eV)")
    axis.set_ylabel("DOS (states/eV)")
    axis.set_xlim(args.xmin, args.xmax)
    axis.set_ylim(bottom=0)
    axis.legend(loc="upper right")
    figure.savefig(args.output, dpi=180)


if __name__ == "__main__":
    main()
