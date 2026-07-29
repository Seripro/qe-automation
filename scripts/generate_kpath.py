#!/usr/bin/env python3
"""
pwscf.in から結晶構造を読み取り、SeeK-path で K点パスを自動生成して
kp.pwscf を出力するスクリプト。

使い方:
    python generate_kpath.py pwscf.in [npoints]

    npoints: 各セグメントの分割数 (デフォルト: 20)

必要なパッケージ:
    pip install seekpath numpy
"""

import sys
import re
import numpy as np
import seekpath

ATOMIC_NUMBERS = {
    'H': 1, 'He': 2, 'Li': 3, 'Be': 4, 'B': 5, 'C': 6, 'N': 7, 'O': 8,
    'F': 9, 'Ne': 10, 'Na': 11, 'Mg': 12, 'Al': 13, 'Si': 14, 'P': 15,
    'S': 16, 'Cl': 17, 'Ar': 18, 'K': 19, 'Ca': 20, 'Sc': 21, 'Ti': 22,
    'V': 23, 'Cr': 24, 'Mn': 25, 'Fe': 26, 'Co': 27, 'Ni': 28, 'Cu': 29,
    'Zn': 30, 'Ga': 31, 'Ge': 32, 'As': 33, 'Se': 34, 'Br': 35, 'Kr': 36,
    'Rb': 37, 'Sr': 38, 'Y': 39, 'Zr': 40, 'Nb': 41, 'Mo': 42, 'Tc': 43,
    'Ru': 44, 'Rh': 45, 'Pd': 46, 'Ag': 47, 'Cd': 48, 'In': 49, 'Sn': 50,
    'Sb': 51, 'Te': 52, 'I': 53, 'Xe': 54, 'Cs': 55, 'Ba': 56, 'La': 57,
    'Ce': 58, 'Pr': 59, 'Nd': 60, 'Pm': 61, 'Sm': 62, 'Eu': 63, 'Gd': 64,
    'Tb': 65, 'Dy': 66, 'Ho': 67, 'Er': 68, 'Tm': 69, 'Yb': 70, 'Lu': 71,
    'Hf': 72, 'Ta': 73, 'W': 74, 'Re': 75, 'Os': 76, 'Ir': 77, 'Pt': 78,
    'Au': 79, 'Hg': 80, 'Tl': 81, 'Pb': 82, 'Bi': 83, 'Po': 84, 'At': 85,
    'Rn': 86, 'Fr': 87, 'Ra': 88, 'Ac': 89, 'Th': 90, 'Pa': 91, 'U': 92,
    'Np': 93, 'Pu': 94, 'Am': 95, 'Cm': 96,
}


def parse_pwscf_input(filename):
    """pwscf.in を解析して cell, positions, numbers を返す"""
    with open(filename, 'r') as f:
        lines = f.readlines()

    content = ''.join(lines)

    # ibrav を取得
    ibrav_match = re.search(r'ibrav\s*=\s*(\d+)', content)
    ibrav = int(ibrav_match.group(1)) if ibrav_match else 0

    # nat (原子数) を取得
    nat_match = re.search(r'nat\s*=\s*(\d+)', content)
    nat = int(nat_match.group(1))

    # セルパラメータの取得
    cell = None
    if ibrav == 0:
        cell = parse_cell_parameters(lines)
    else:
        cell = construct_cell_from_ibrav(ibrav, content)

    # 原子座標の取得
    positions, species = parse_atomic_positions(lines, nat)

    # 元素記号 -> 原子番号
    numbers = [ATOMIC_NUMBERS[s] for s in species]

    return cell, positions, numbers


def parse_cell_parameters(lines):
    """CELL_PARAMETERS セクションを解析"""
    cell = []
    in_cell = False
    unit = 'bohr'

    for line in lines:
        stripped = line.strip()
        if stripped.upper().startswith('CELL_PARAMETERS'):
            in_cell = True
            if 'angstrom' in stripped.lower():
                unit = 'angstrom'
            elif 'bohr' in stripped.lower():
                unit = 'bohr'
            else:
                unit = 'alat'
            continue
        if in_cell:
            if stripped == '' or stripped.startswith('&') or stripped.startswith('/'):
                if len(cell) == 3:
                    break
                continue
            parts = stripped.split()
            if len(parts) >= 3:
                try:
                    cell.append([float(parts[0]), float(parts[1]), float(parts[2])])
                except ValueError:
                    break
            if len(cell) == 3:
                break

    cell = np.array(cell)

    # bohr -> angstrom 変換
    if unit == 'bohr':
        cell *= 0.529177

    return cell.tolist()


def construct_cell_from_ibrav(ibrav, content):
    """ibrav と celldm/A から格子ベクトルを構築"""
    # celldm(1) を探す (bohr単位)
    celldm1_match = re.search(r'celldm\(1\)\s*=\s*([\d.eE+-]+)', content)
    a_match = re.search(r'\bA\s*=\s*([\d.eE+-]+)', content)

    if celldm1_match:
        a = float(celldm1_match.group(1)) * 0.529177  # bohr -> angstrom
    elif a_match:
        a = float(a_match.group(1))  # already angstrom
    else:
        raise ValueError("Could not find celldm(1) or A in input file")

    # celldm(3) = c/a for hexagonal
    celldm3_match = re.search(r'celldm\(3\)\s*=\s*([\d.eE+-]+)', content)
    c_over_a = float(celldm3_match.group(1)) if celldm3_match else 1.0

    c = a * c_over_a

    if ibrav == 1:  # Simple Cubic
        return [[a, 0, 0], [0, a, 0], [0, 0, a]]
    elif ibrav == 2:  # FCC
        return [[-a/2, 0, a/2], [0, a/2, a/2], [-a/2, a/2, 0]]
    elif ibrav == 3:  # BCC
        return [[a/2, a/2, a/2], [-a/2, a/2, a/2], [-a/2, -a/2, a/2]]
    elif ibrav == -3:  # BCC (alternative)
        return [[-a/2, a/2, a/2], [a/2, -a/2, a/2], [a/2, a/2, -a/2]]
    elif ibrav == 4:  # Hexagonal
        return [[a, 0, 0], [-a/2, a*np.sqrt(3)/2, 0], [0, 0, c]]
    elif ibrav == 5:  # Trigonal R (3-fold axis c)
        celldm4_match = re.search(r'celldm\(4\)\s*=\s*([\d.eE+-]+)', content)
        cos_alpha = float(celldm4_match.group(1)) if celldm4_match else 0.5
        tx = a * np.sqrt((1 - cos_alpha) / 2)
        ty = a * np.sqrt((1 - cos_alpha) / 6)
        tz = a * np.sqrt((1 + 2*cos_alpha) / 3)
        return [[tx, -ty, tz], [0, 2*ty, tz], [-tx, -ty, tz]]
    elif ibrav == 6:  # Tetragonal P
        return [[a, 0, 0], [0, a, 0], [0, 0, c]]
    elif ibrav == 7:  # Tetragonal I
        return [[a/2, -a/2, c/2], [a/2, a/2, c/2], [-a/2, -a/2, c/2]]
    elif ibrav == 8:  # Orthorhombic P
        celldm2_match = re.search(r'celldm\(2\)\s*=\s*([\d.eE+-]+)', content)
        b_over_a = float(celldm2_match.group(1)) if celldm2_match else 1.0
        b = a * b_over_a
        return [[a, 0, 0], [0, b, 0], [0, 0, c]]
    else:
        raise ValueError(
            f"ibrav={ibrav} is not yet supported by this parser. "
            f"Use ibrav=0 with explicit CELL_PARAMETERS instead."
        )


def parse_atomic_positions(lines, nat):
    """ATOMIC_POSITIONS セクションを解析"""
    positions = []
    species = []
    in_positions = False
    coord_type = 'crystal'

    for line in lines:
        stripped = line.strip()
        if stripped.upper().startswith('ATOMIC_POSITIONS'):
            in_positions = True
            if 'angstrom' in stripped.lower():
                coord_type = 'angstrom'
            elif 'bohr' in stripped.lower():
                coord_type = 'bohr'
            elif 'crystal' in stripped.lower():
                coord_type = 'crystal'
            else:
                coord_type = 'alat'
            continue
        if in_positions:
            if stripped == '' or stripped.startswith('&') or stripped.startswith('/'):
                if len(positions) >= nat:
                    break
                continue
            parts = stripped.split()
            if len(parts) >= 4:
                try:
                    species.append(parts[0])
                    positions.append([float(parts[1]), float(parts[2]), float(parts[3])])
                except ValueError:
                    break
            if len(positions) >= nat:
                break

    if coord_type != 'crystal':
        print(f"Warning: ATOMIC_POSITIONS is in '{coord_type}' format.", file=sys.stderr)
        print("SeeK-path expects fractional (crystal) coordinates.", file=sys.stderr)
        print("Results may be incorrect if coordinates are not fractional.", file=sys.stderr)

    return positions, species


def generate_kp_pwscf(result, npoints=20):
    """SeeK-path の結果から kp.pwscf の内容を生成"""
    path = result['path']
    point_coords = result['point_coords']

    # パス上のユニークな点を順に列挙
    kpoints = []
    for i, (start, end) in enumerate(path):
        if i == 0:
            coord = point_coords[start]
            label = start.replace('GAMMA', 'Gamma')
            kpoints.append((coord, npoints, label))

        coord = point_coords[end]
        label = end.replace('GAMMA', 'Gamma')
        # セグメントの最後の点: 次のセグメントの始点と一致する場合は npoints
        # パスの最終点は 0（または npoints）
        if i < len(path) - 1:
            next_start = path[i + 1][0]
            if end == next_start:
                kpoints.append((coord, npoints, label))
            else:
                # 不連続点（ジャンプ）: npoints=0で区切る
                kpoints.append((coord, 0, label))
                # 次の始点を追加
                next_coord = point_coords[next_start]
                next_label = next_start.replace('GAMMA', 'Gamma')
                kpoints.append((next_coord, npoints, next_label))
        else:
            kpoints.append((coord, 0, label))

    output = f"K_POINTS {{crystal_b}}\n"
    output += f"{len(kpoints)}\n"
    for coord, npts, label in kpoints:
        output += f"{coord[0]:.6f} {coord[1]:.6f} {coord[2]:.6f}  {npts} ! {label}\n"

    return output


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_kpath.py pwscf.in [npoints]", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]
    npoints = int(sys.argv[2]) if len(sys.argv) > 2 else 20

    print(f"Reading {input_file}...", file=sys.stderr)
    cell, positions, numbers = parse_pwscf_input(input_file)

    print(f"  Cell vectors:", file=sys.stderr)
    for v in cell:
        print(f"    {v}", file=sys.stderr)
    print(f"  Number of atoms: {len(positions)}", file=sys.stderr)
    print(f"  Atomic numbers: {numbers}", file=sys.stderr)

    structure = (cell, positions, numbers)
    result = seekpath.get_path(structure)

    print(f"  Detected Bravais lattice: {result.get('bravais_lattice', 'unknown')}", file=sys.stderr)
    print(f"  Path: {' -> '.join([s for pair in result['path'] for s in pair][::2] + [result['path'][-1][1]])}", file=sys.stderr)

    kp_content = generate_kp_pwscf(result, npoints)

    # kp.pwscf に出力
    output_file = "kp.pwscf"
    with open(output_file, 'w') as f:
        f.write(kp_content)

    print(f"  Written to {output_file}", file=sys.stderr)
    print(kp_content, file=sys.stderr)


if __name__ == '__main__':
    main()
