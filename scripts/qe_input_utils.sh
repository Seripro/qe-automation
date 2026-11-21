#!/usr/bin/env bash
# Common helpers for the QE input files produced with PWscf.zip.

# Print the final value assigned to a CONTROL namelist setting.  This covers
# the usual `prefix = 'value'` and `outdir = './path/'` notation.
qe_control_value() {
    local input_file="$1"
    local setting="$2"

    sed -nE "s/^[[:space:]]*${setting}[[:space:]]*=[[:space:]]*['\"]?([^,'\"[:space:]]+)['\"]?.*/\\1/p" "${input_file}" | tail -n 1
}

# Print the ATOMIC_SPECIES labels, one per line, in the order in the input.
qe_atomic_species_labels() {
    local input_file="$1"

    awk '
        /^[[:space:]]*ATOMIC_SPECIES([[:space:]]|$)/ { reading = 1; next }
        reading && /^[[:space:]]*(ATOMIC_POSITIONS|K_POINTS|CELL_PARAMETERS|CONSTRAINTS|OCCUPATIONS)([[:space:]]|$)/ { exit }
        reading && NF >= 3 { print $1 }
    ' "${input_file}"
}

# Print the pseudopotential filenames listed in ATOMIC_SPECIES, one per line.
qe_pseudopotential_files() {
    local input_file="$1"

    awk '
        /^[[:space:]]*ATOMIC_SPECIES([[:space:]]|$)/ { reading = 1; next }
        reading && /^[[:space:]]*(ATOMIC_POSITIONS|K_POINTS|CELL_PARAMETERS|CONSTRAINTS|OCCUPATIONS)([[:space:]]|$)/ { exit }
        reading && NF >= 3 { print $3 }
    ' "${input_file}"
}

# Resolve QE's outdir relative to the directory containing pwscf.in.
qe_outdir_path() {
    local calculation_dir="$1"
    local outdir="$2"

    if [[ "${outdir}" = /* ]]; then
        printf '%s\n' "${outdir}"
    else
        printf '%s/%s\n' "${calculation_dir}" "${outdir#./}"
    fi
}
