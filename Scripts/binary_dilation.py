import os
import sys
import numpy as np
import nibabel as nib
import scipy
import skimage
import argparse
from scipy.ndimage import binary_dilation
from scipy.ndimage import binary_erosion, generate_binary_structure, iterate_structure
from skimage.morphology import ball

print("Python:", sys.version)
print("numpy:", np.__version__)
print("nibabel:", nib.__version__)
print("scipy:", scipy.__version__)
print("scikit-image:", skimage.__version__)

parser = argparse.ArgumentParser()
parser.add_argument(
    "--subj",
    nargs="+",
    required=True,
    help="One or more subject IDs")

parser.add_argument(
    "--input_path",
    required=True,
    help="Base input directory")

args = parser.parse_args()
base_path = args.input_path

for subject in args.subj:
    suitDerivativesPath = os.path.join(base_path, subject, 'SUIT_Derivatives')

    crus_I_dilated_file = os.path.join(suitDerivativesPath, f'Cereb-SUIT_Atlas_Crus_I_{subject}_dilated.nii.gz')
    output_file_dilated = os.path.join(suitDerivativesPath, f'maskSUIT_warp_2_{subject}_native_T1_dilated.nii')

    if not os.path.exists(output_file_dilated):
        print(f"Processing subject: {subject}")

        mask_file = os.path.join(suitDerivativesPath, f'maskSUIT_warp_2_{subject}_native_T1_bin.nii.gz')
        atlas_gm_file = os.path.join(suitDerivativesPath, f'Cereb-SUIT_Atlas_GM_{subject}.nii.gz')
        crus_II_VIIb_file = os.path.join(suitDerivativesPath, f'Cereb-SUIT_Atlas_Crus_II_VIIb_{subject}.nii.gz')
        lob_V_I_IV_file = os.path.join(suitDerivativesPath, f'Cereb-SUIT_Atlas_Lob_V_I-IV_{subject}.nii.gz')
        crus_I_file = os.path.join(suitDerivativesPath, f'Cereb-SUIT_Atlas_Crus_I_{subject}.nii.gz')

        # Load images
        mask_img = nib.load(mask_file)
        gm_img = nib.load(atlas_gm_file)
        crus_II_VIIb_img = nib.load(crus_II_VIIb_file)
        lob_V_I_IV_img = nib.load(lob_V_I_IV_file)
        crus_I_img = nib.load(crus_I_file)

        mask_data = mask_img.get_fdata() > 0
        gm_data = gm_img.get_fdata() > 0
        crus_II_VIIb_data = crus_II_VIIb_img.get_fdata() > 0
        lob_V_I_IV_data = lob_V_I_IV_img.get_fdata() > 0
        crus_I_data = crus_I_img.get_fdata() > 0

        # Dilation steps
        dilated_mask_I = binary_dilation(mask_data, structure=None, iterations=1, mask=gm_data)
        dilated_mask_II = binary_dilation(dilated_mask_I, structure=None, iterations=3, mask=crus_II_VIIb_data)
        dilated_mask_III = binary_dilation(dilated_mask_II, structure=None, iterations=1, mask=lob_V_I_IV_data)

        # Erode and Dilate Crus I
        struct_spherical = ball(radius=1.5).astype(np.uint8)
        crus_I_eroded = binary_erosion(crus_I_data, structure=struct_spherical, iterations=1)
        crus_I_dilated = binary_dilation(crus_I_eroded, structure=struct_spherical, iterations=2)
        nib.save(nib.Nifti1Image(crus_I_dilated.astype(np.uint8), mask_img.affine, mask_img.header), crus_I_dilated_file)

        # Round 4 dilation with Crus I
        dilated_mask_IV = binary_dilation(dilated_mask_III, structure=struct_spherical, iterations=1, mask=crus_I_dilated)

        # Save
        nib.save(nib.Nifti1Image(dilated_mask_IV.astype(np.uint8), mask_img.affine, mask_img.header), output_file_dilated)
        print(f"Saved dilated mask: {output_file_dilated}")

    else:
        print(f"Skipping {subject}, output already exists.")