#!/bin/bash

subj="$1"
DIROUT="$2"
MPRAGE="$3"
Repo_path="$4"
antspath="$5"

# Resolve and validate the MNI template (see Templates.md)
MNI_TEMPLATE="${Repo_path}/Templates/mni_icbm152_t1_tal_nlin_asym_09c.nii"
[ -s "${MNI_TEMPLATE}" ] || { echo "ERROR: MNI template missing at ${MNI_TEMPLATE} — see Templates.md" >&2; exit 1; }

# Copy over the matching T1 image
mkdir -p "${DIROUT}/${subj}"
SUIT_DIR="${DIROUT}/${subj}/SUIT_Derivatives"
mkdir -p "${SUIT_DIR}"

if [ ! -f "${SUIT_DIR}/${subj}_N4_native.nii" ]; then
    if [[ "${MPRAGE}" == *.nii.gz ]]; then
        cp "${MPRAGE}" "${SUIT_DIR}/${subj}_N4_native.nii.gz"
        gunzip "${SUIT_DIR}/${subj}_N4_native.nii.gz"
    else
        cp "${MPRAGE}" "${SUIT_DIR}/${subj}_N4_native.nii"
    fi
fi   	

# Create a log directory for ANTs run
LOG_DIR="${SUIT_DIR}/Processing_Logs_SUIT"
mkdir -p "$LOG_DIR"  
LOG_FILE="${LOG_DIR}/${subj}_ANTs_mnicoreg_$(date '+%Y%m%d_%H%M%S').log"

run_and_log() {
    echo "Running: $*" | tee -a "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1
    local status=$?
    if [ $status -ne 0 ]; then
        echo "ERROR: Command failed with exit code $status: $*" | tee -a "$LOG_FILE"
    fi
    return $status
}

# ACPC alignment 
if [ ! -f "${SUIT_DIR}/${subj}_T1_to_MNI_0GenericAffine.mat" ]; then
    cd "$SUIT_DIR"
    run_and_log "${antspath}/antsRegistrationSyNQuick.sh" -d 3 \
        -f "${Repo_path}/Templates/mni_icbm152_t1_tal_nlin_asym_09c.nii" \
        -m "${subj}_N4_native.nii" \
        -o "${subj}_T1_to_MNI_"
fi

# ANTs apply transforms
if [ ! -f "${SUIT_DIR}/${subj}_N4_ACPC.nii" ]; then
    run_and_log "${antspath}/antsApplyTransforms" -d 3 \
        -i "${SUIT_DIR}/${subj}_N4_native.nii" \
        -r "${Repo_path}/Templates/mni_icbm152_t1_tal_nlin_asym_09c.nii" \
        -t "${SUIT_DIR}/${subj}_T1_to_MNI_1Warp.nii.gz" \
        -t "${SUIT_DIR}/${subj}_T1_to_MNI_0GenericAffine.mat" \
        -o "${SUIT_DIR}/${subj}_N4_ACPC.nii" -v
fi
