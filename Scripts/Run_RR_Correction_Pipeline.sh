#!/bin/bash

read -p "Enter subject ID: " subject
read -p "Enter output directory: " DIROUT
read -p "Enter path to T1 image: " MPRAGE
read -p "Enter path to cloned repo: " Repo_path
read -p "Enter SPM12 path: " spm12_path
read -p "Enter ANTs path: " antspath
read -p "Enter FSL path: " fslpath
read -p "Enter Python executable: " pyExe
read -p "Enter full path to original cerebellum mask: " original_cereb_mask

cd ${Repo_path}/Scripts

# Run ACPC Alignment Script
SUIT_Derivatives="${DIROUT}/${subject}/SUIT_Derivatives"
if [ ! -f "${SUIT_Derivatives}/${subject}_N4_ACPC.nii" ]; then
    ./SUIT_Prep.sh "$subject" "$DIROUT" "$MPRAGE" "$Repo_path" "$antspath"
fi

#Run MATLAB SUIT to extract corrected mask 
SUIT_Final_Output="${DIROUT}/${subject}/SUIT_Main_Outputs"
mask_file="${SUIT_Final_Output}/${subject}_aparc+aseg_native_ref_cerebellum-whole_bin-CORRECTED.nii.gz"

if [ ! -f "$mask_file" ]; then
	matlab -nodesktop -nosplash -r "Fix_Cerebellum_SUIT('$Repo_path','$spm12_path','$antspath','$fslpath','$pyExe','$subject','$original_cereb_mask','$DIROUT'); exit;"
fi

chmod -R 770 "${SUIT_Derivatives}"
chmod -R 770 "${SUIT_Final_Output}"
