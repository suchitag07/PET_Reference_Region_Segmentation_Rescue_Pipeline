## Amyloid-PET Reference Region Rescue Pipeline

### Scripts and Dependencies
- This doc will systematically go over the scripts/code used to implement this correction method.

### Software:
- MATLAB R2019b
- SPM12 release 6685
- SUIT version 3.0
- FSL (version 5.0.9)
- Advanced Normalization Tools (ANTs)
- Python version 3.9 with SciPy: 1.10

### Templates
- Download the SUIT and MNI templates as specified in the documentation and store them inside a separate Templates directory (`SUIT_Prep.sh` relies on this).

### Scripts
- After you install all dependencies, you should be ready to run the following scripts:
    - [Main Master Script: Run_RR_Correction_Pipeline.sh](https://github.com/suchitag07/PET_Reference_Region_Segmentation_Rescue_Pipeline/blob/main/Instructions_Scripts.md#master-script-run_rr_correction_pipelinesh)
	- [Subscript 1: ACPC Alignment Script: `SUIT_Prep.sh`](https://github.com/suchitag07/PET_Reference_Region_Segmentation_Rescue_Pipeline/blob/main/Instructions_Scripts.md#suit_prepsh--acpc-alignment-script
)
	- [Subscript 2: Fix-Cerebellum_SUIT Matlab Function: `Fix_Cerebellum_SUIT.m`](https://github.com/suchitag07/PET_Reference_Region_Segmentation_Rescue_Pipeline/blob/main/Instructions_Scripts.md#fix_cerebellum_suitm-function
)
	- [Subscript 3: Mask Dilation Script: `binary_dilation.py`](https://github.com/suchitag07/PET_Reference_Region_Segmentation_Rescue_Pipeline/blob/main/Instructions_Scripts.md#iiid--targeted-dilation-using-suit-subregions
)
	- [Optional - Coregistration of Corrected-Mask to PET Space: `Coreg_Corrected_RR_to_PET.sh`](https://github.com/suchitag07/PET_Reference_Region_Segmentation_Rescue_Pipeline/blob/main/Instructions_Scripts.md#fix_cerebellum_suitm-block-iv-derive-corrected-mask)

***

## Master-Script: `Run_RR_Correction_Pipeline.sh`									

- As as user, this is the only script you'll have to toggle with in order to run the pipeline (a simple `./Run_RR_Correction_Pipeline.sh` call is all that's needed). 
- It will prompt you to enter paths to all input data - your T1 image, the original faulty segmentation file - the paths to all software dependencies etc.
- Once it's done runnning, you should find the corrected image segmentation file under `SUIT_Main_Outputs/sub-01_aparc+aseg_native_ref_cerebellum-whole_bin-CORRECTED.nii.gz`. The corrected file is in native T1 space. In order to register this to PET space, you would need to apply your PET-T1 coregistration transforms - the format of which will vary according to registration method you've chosen.
- That's it!
- More details regarding the sub-scribts can be found below.

***

## `SUIT_Prep.sh`:  ACPC Alignment Script					

This script performs rigid and nonlinear registration of each subject’s native T1 MRI image to the MNI-ICBM152 anatomical template using ANTs. The process involves two steps: registering the native image and applying the transformations to create an ACPC-aligned T1 image that is ready for use with the SUIT toolbox.

- **Registration:**  
  Runs `antsRegistrationSyNQuick.sh` to align the native T1 image to the MNI template, producing affine and warp field outputs.
- **Transformation:**  
  Applies both the affine and nonlinear warp transforms to generate an ACPC-aligned T1 image.

### Code Block

```bash
#!/bin/bash

subj="$1"
DIROUT="$2"
MPRAGE="$3"
Repo_path="$4"
antspath="$5"

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
    
```
***

## `Fix_Cerebellum_SUIT.m` Function 

This is a heavy matlab function that calls on the `SUIT` toolbox and derivative masks/atlases.

***Processing Steps Overview***

1. Isolates cerebellum and brainstem (`suit_isolate_seg`)
2. Extracts deformation field to/from SUIT and MNI space (`suit_normalize`)
3. Reslices SUIT masks/atlas to native T1 space (`suit_reslice_inverse`, `antsApplyTransforms`)
4. Generates modified mask by constrained dilation (`binary_dilation.py`)
5. Final intersection masks created via `fslmaths`

***

## Fix_Cerebellum_SUIT Code Breakdown (In Parts)

### Code Block (Path Setup)

```matlab
function Fix_Cerebellum_SUIT(Repo_path, spm12_path, antspath, fslpath, pyExe, subject_in, original_cereb_mask, out_dir)
%
% Wriiten by SG - 04/16/2025
%__________________________________________________________________________
%
%  Inputs: ${subject_id}_N4_ACPC.nii (T1) 
%
%  Main outputs: Corrected RR mask
%  Processing log located here: ${subject_id}/SUIT_Derivatives/Processing_Logs_SUIT
%__________________________________________________________________________
%
%  Summary of Processing Steps:
%  I) Isolate the cerebellum and brainstem: suit_isolate_seg
%  II) Extract deformation field to move between SUIT and native space: suit_normalize
%  III) Reslice the SUIT mask into T1 native space: suit_reslice_inverse + antsApplyTransforms 
%  IV) Derive intersection between transformed SUIT and original RR mask (fslmaths)
%__________________________________________________________________________
%
%% SETTING UP PATHS
%__________________________________________________________________________

    addpath(genpath(spm12_path)); 
    addpath(fullfile(spm12_path,'toolbox','suit'));
    addpath(antspath);
    addpath(fslpath);
    
    spm_get_defaults;
    subject = subject_in;
    
    % Select directory where ACPC aligned T1 is stored
    Subject_Path = fullfile(out_dir, subject);
    suitDerivativesPath = fullfile(Subject_Path, 'SUIT_Derivatives');
	T1_File = fullfile(suitDerivativesPath, sprintf('%s_N4_ACPC.nii', subject));
    
    % Create suitMainOutputsPath to store Intersection mask in T1 and final PET space masks
    suitMainOutputsPath = fullfile(Subject_Path, 'SUIT_Main_Outputs');
    if ~exist(suitMainOutputsPath, 'dir')
        mkdir(suitMainOutputsPath);
    end
    
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    log_filename = sprintf('SUIT_extract_cerebellum_log_%s.txt', timestamp);

    % Log directory inside the visit directory
    log_directory = fullfile(suitDerivativesPath, 'Processing_Logs_SUIT');

    if ~exist(log_directory, 'dir')
        mkdir(log_directory);
    end
    
    log_filepath = fullfile(log_directory, log_filename);
    diary(log_filepath);
    diary on;
    
    fprintf('\n');
    verInfo = spm('version');
    fprintf('Current SPM version: %s\n', verInfo);
    fprintf('\n');
    
    [~, hostname] = system('hostname');
	hostname = strtrim(hostname); % Remove trailing newline from system output
	username = getenv('USER');
	fprintf('HOSTNAME: %s\n', hostname);
	fprintf('USERNAME: %s\n', username);

	
    fprintf('Path to input T1 file: %s\n', T1_File);
	fprintf('Subject ID: %s\n', subject);
    
    % Copy maskSUIT.nii and SUIT atlas files to suitDerivativesPath
    templatesPath = fullfile(spm12_path, 'toolbox', 'suit', 'templates');
    atlasPath = fullfile(spm12_path, 'toolbox', 'suit', 'atlas');
    SUIT_mask = fullfile(suitDerivativesPath, 'maskSUIT.nii');
    SUIT_atlas = fullfile(suitDerivativesPath, 'Cerebellum-SUIT.nii');
    
    if ~exist(SUIT_mask, 'file')
        copyfile(fullfile(templatesPath, "maskSUIT.nii"), suitDerivativesPath);
    end
    
    if ~exist(SUIT_atlas, 'file')
        copyfile(fullfile(atlasPath, "Cerebellum-SUIT.nii"), suitDerivativesPath);
    end
    
    
    cd(suitDerivativesPath);
```
***

## Fix_Cerebellum_SUIT.m Block I: Isolate Cerebellum and Brainstem : `suit_isolate_seg`

- After we isolate the cerebellum to improve registration of the atlas to native space, we apply MATLAB’s SUIT toolbox functions to the T1-weighted image. 
- First, we use the function suit_isolate_seg to generate a cropped binary mask of the cerebellum/brainstem. 

```matlab
% STEP I: ISOLATE SEG 
%__________________________________________________________________________

    Source = fullfile(suitDerivativesPath, sprintf('%s_N4_ACPC.nii', subject));
    seg = fullfile(suitDerivativesPath, sprintf('c_%s_N4_ACPC_pcereb.nii', subject));  % T1 space mask -> output of seg step
    if ~exist(seg, 'file')
        suit_isolate_seg({Source});
    end

```
***

## Fix_Cerebellum_SUIT.m Block II: Normalization (SUIT → Native) : `suit_normalize`

- The function suit_normalize accepts the cropped images and performs affine (linear) and non-linear transformations to align the subject’s segmented cerebellum/brainstem image with SUIT space. In the process, it outputs a deformation field.
- Note: We do not use the cropped mask or tissue segmentation files produced by suit_isolate_seg for further processing as they may occasionally encroach into the meninges. 


```matlab
% STEP II: NORMALIZATION
%__________________________________________________________________________

    norm_file = fullfile(suitDerivativesPath, sprintf('mc_%s_N4_ACPC.nii', subject)); % <- resliced image
        
    if ~exist(norm_file, 'file')
        suit_normalize(sprintf('c_%s_N4_ACPC.nii', subject) , 'mask', sprintf('c_%s_N4_ACPC_pcereb.nii', subject)); 
    end
        
    img = niftiread(norm_file); % Read the resliced image file
	if any(isnan(img(:))) || max(img(:)) <= 1
    	fprintf('ERROR: The resliced image (%s) contains NaN values.\n', norm_file);
    	diary off;
    	return;  % Exit the function if the image is invalid
	else
    	fprintf('\nRESLICED IMAGE (%s) IS VALID.\n', norm_file); % Confirm the image is valid
	end
                
    mask_file = fullfile(suitDerivativesPath, sprintf('c_%s_N4_ACPC_pcereb.nii', subject)); % T1 space mask -> output of seg step
    mat_file = fullfile(suitDerivativesPath, sprintf('mc_%s_N4_ACPC_snc.mat', subject)); % Deformation field -> output of normalization step
```
![](https://github.com/user-attachments/assets/07ecf5a4-cc4f-4c28-b068-5b2317a7e068)

***

## Fix_Cerebellum_SUIT.m Block III: Transform SUIT Mask and Atlas : `suit_reslice_inv`

- Inverse warp to MNI space: 
	- The deformation field that results from normalizing the cerebellum to SUIT space is then applied to the binary mask ‘maskSUIT.nii’ using (suit_reslice_inv) to bring it into ACPC/MNI aligned space (where our T1 image currently is). 
- Final warp to native space: 
	- The inverse of the transformation matrices obtained from step 1 (T1-MNI space coregistration) are applied to bring the MNI aligned SUIT mask back into native T1-weighted image space (antsApplyTransforms with the Nearest Neighbor interpolation method). 


### IIIA Reverse Normalization of SUIT-Binary Mask to Native Space

```matlab
% STEP III A: RESLLICE SUIT mask to native space 
%__________________________________________________________________________

	inversewarp_suit_MASK  = fullfile(suitDerivativesPath, 'iw_maskSUIT.nii');

	if ~exist(inversewarp_suit_MASK, 'file')  
		prefix = 'iw_';
    	suit_reslice_inv('maskSUIT.nii', sprintf('mc_%s_N4_ACPC_snc.mat', subject), 'prefix', prefix); % output is iw_maskSUIT.nii
	end

	% Re-Binarize after warp I
	inversewarp_suit_MASK_BIN = sprintf('%s/iw_maskSUIT_bin.nii.gz', suitDerivativesPath);
	
	if ~exist(inversewarp_suit_MASK_BIN, 'file')
		cmd1 = sprintf('%s/fslmaths %s/iw_maskSUIT.nii -bin %s/iw_maskSUIT_bin.nii.gz', fslpath, suitDerivativesPath, suitDerivativesPath);
		system(cmd1);
    	fprintf('\nExecuted command: %s\n', cmd1);
	end	

	SUITmask_resliced = fullfile(suitDerivativesPath, sprintf('maskSUIT_warp_2_%s_native_T1.nii', subject)); 
	     
	if ~exist(SUITmask_resliced, 'file')
    	% Final transformation to native T1
    	command_transform = sprintf(['%s/antsApplyTransforms -d 3 -e 0 --float 0 ' ...
        	'-i %s/iw_maskSUIT.nii -r %s/%s_N4_native.nii ' ...
        	'-n NearestNeighbor ' ...
        	'-t [%s_T1_to_MNI_0GenericAffine.mat,1] ' ...
        	'-t %s_T1_to_MNI_1InverseWarp.nii.gz ' ...
        	'-o %s/maskSUIT_warp_2_%s_native_T1.nii'], ...
        	antspath, suitDerivativesPath, suitDerivativesPath, subject, subject, subject, suitDerivativesPath, subject);

    	fprintf('\nExecuting command: %s\n', command_transform);
    	[status, result] = system(command_transform);
    	disp(result);
	end

	% Re-Binarize after warp II
	SUITmask_resliced_BIN = fullfile(suitDerivativesPath, sprintf('maskSUIT_warp_2_%s_native_T1_bin.nii.gz', subject));    
	  
	if ~exist(SUITmask_resliced_BIN, 'file')
		cmd1 = sprintf(['%s/fslmaths %s/maskSUIT_warp_2_%s_native_T1.nii -bin %s/maskSUIT_warp_2_%s_native_T1_bin.nii.gz'], fslpath, suitDerivativesPath, subject, suitDerivativesPath, subject);
		system(cmd1);
    	fprintf('\nExecuted command: %s\n', cmd1);
	end
	
```
![](https://github.com/user-attachments/assets/0581ee95-ada4-4400-9435-241131b35a7d)

***

### IIIB Reverse Normalization of the SUIT Atlas to Native Space and Extraction of Atlas Sub-regions

- The SUIT binary mask sometimes undersegments the cerebellum in specific standard subregions. 
- To address this, in addition to registering the SUIT binary mask to native space, we use the same set of transformation steps to bring the SUIT probabilistic atlas to native space. 
- This SUIT probabilistic atlas covers 28 lobules (10 pairs hemispheric and 8 vermal). 
- We leverage the atlas subregions to refine the binary mask in areas that tend to be problematic.
- Once in native space, we threshold out the following as subregion masks (fslmaths) (Figure 6). 
	- SUIT Cerebellar GM mask: Codes 1-28, 33, and 34
	- SUIT Lobules I-V mask: Codes 1-4
	- SUIT Crus II and IIVb mask: Codes 11 to 16
	- SUIT Crus I mask: Codes 8 to 10

```matlab
% STEP III B: RESLICE SUIT PROBABILISTIC ATLAS to native space
%__________________________________________________________________________

	inversewarp_suit_ATLAS = fullfile(suitDerivativesPath, 'iw_Cerebellum-SUIT.nii');		
	
	if ~exist(inversewarp_suit_ATLAS, 'file')  
		prefix = 'iw_';
    	suit_reslice_inv('Cerebellum-SUIT.nii', sprintf('mc_%s_N4_ACPC_snc.mat', subject), 'prefix', prefix); % output is iw_Cerebellum-SUIT.nii
	end

	SUIT_ATLAS_resliced = fullfile(suitDerivativesPath, sprintf('Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii', subject));   
	   
    if ~exist(SUIT_ATLAS_resliced, 'file')
    	% First transformation to native T1
    	command_transform = sprintf(['%s/antsApplyTransforms -d 3 -e 0 --float 0 ' ...
        	'-i %s/iw_Cerebellum-SUIT.nii -r %s/%s_N4_native.nii ' ...
        	'-n NearestNeighbor ' ...
        	'-t [%s_T1_to_MNI_0GenericAffine.mat,1] ' ...
        	'-t %s_T1_to_MNI_1InverseWarp.nii.gz ' ...
        	'-o %s/Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii'], ...
        	antspath, suitDerivativesPath, suitDerivativesPath, subject, subject, subject, suitDerivativesPath, subject);

    	fprintf('\nExecuting command: %s\n', command_transform);
    	[status, result] = system(command_transform);
    	disp(result);
	end

# DO NOT RE-BINARIZE YET ---> THRESHOLD TO GET ATLAS SUBREGION AND THEN BINARIZE
```

***

### IIIC Extraction of GM Subregions

```matlab
% STEP III C: EXTRACT GM SUBREGIONS from SUIT PROBABILISTIC ATLAS -> To constrain dilation
%____________________________________________________________________________________________________________

	ATLAS_GM = fullfile(suitDerivativesPath, sprintf('Cereb-SUIT_Atlas_GM_%s.nii.gz', subject));
	Crus_I = fullfile(suitDerivativesPath, sprintf('Cereb-SUIT_Atlas_Crus_I_%s.nii.gz', subject));
	Neo_CB_GM = fullfile(suitDerivativesPath, sprintf('Cereb-SUIT_Atlas_Crus_II_VIIb_%s.nii.gz', subject));
	Lobule_V_I_IV = fullfile(suitDerivativesPath, sprintf('Cereb-SUIT_Atlas_Lob_V_I-IV_%s.nii.gz', subject));

	if ~exist(ATLAS_GM, 'file')
    	% Extract GM Mask
    	cmd1 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 1 -uthr 28 -bin Cereb-SUIT_1-28.nii.gz', fslpath, subject);
    	cmd2 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 33 -uthr 33 -bin Cereb-SUIT_33.nii.gz', fslpath, subject);
    	cmd3 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 34 -uthr 34 -bin Cereb-SUIT_34.nii.gz', fslpath, subject);
    	cmd4 = sprintf('%s/fslmaths Cereb-SUIT_1-28.nii.gz -add Cereb-SUIT_33.nii.gz -add Cereb-SUIT_34.nii.gz Cereb-SUIT_Atlas_GM_%s.nii.gz', fslpath, subject);
    	system(cmd1);
    	fprintf('\nExecuted command: %s\n', cmd1);
    	system(cmd2);
    	fprintf('\nExecuted command: %s\n', cmd2);
    	system(cmd3);
    	fprintf('\nExecuted command: %s\n', cmd3);
    	system(cmd4);
    	fprintf('\nExecuted command: %s\n', cmd4);
	end

	if ~exist(Neo_CB_GM, 'file')
    	cmd1 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 11 -uthr 16 -bin Cereb-SUIT_Atlas_Crus_II_VIIb_%s.nii.gz', fslpath, subject, subject);
    	system(cmd1);
    	fprintf('\nExecuted command: %s', cmd1);
	end

	if ~exist(Lobule_V_I_IV, 'file')
    	cmd1 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 1 -uthr 4 -bin Cereb-SUIT_Atlas_Lob_V_I-IV_%s.nii.gz', fslpath, subject, subject);
    	system(cmd1);
    	fprintf('Executed command: %s', cmd1);
	end

	if ~exist(Crus_I, 'file')
    	cmd1 = sprintf('%s/fslmaths Cerebellum_atlas_SUIT_warp_2_%s_native_T1.nii -thr 8 -uthr 10 -bin Cereb-SUIT_Atlas_Crus_I_%s.nii.gz', fslpath, subject, subject);
    	system(cmd1);
    	fprintf('Executed command: %s\n', cmd1);
	end
```

![](https://github.com/user-attachments/assets/491f223f-824c-469b-87e9-e7dc83fa50b5)

***

### IIID : Targeted Dilation using SUIT Subregions 

- We use the scipy.ndimage binary_dilation function to modify the binary mask, passing in the raw mask and the subregion mask(s) as input arguments. 
- The function will dilate all voxels in the binary mask that are specifically covered by that subregion. Eg (dilated_mask = binary_dilation(input_mask, structure=None, iterations=1, mask=Crus_I_mask).
- Summary of the extent to which each subregion is dilated in our pipeline:
	- SUIT Cerebellar GM lobule: Single iteration
	- SUIT Lobules I-V lobule: Single iteration
	- SUIT Crus II and IIVb lobules: Three iterations
	- SUIT Crus I lobule: This lobule mask first undergoes a single round of erosion, followed by two iterations of dilation. The modified Crus I mask is applied in a final dilation step for two iterations.

- Through this method, the dilation is constrained by the limits of each subregion mask; avoiding accidental encroachment into non-cerebellar areas.

```matlab
% STEP III D: MODIFY SUIT MASK
%_________________________________________________________________________

	modified_SUIT = fullfile(suitDerivativesPath, sprintf('maskSUIT_warp_2_%s_native_T1_dilated.nii', subject));

	if ~exist(modified_SUIT, 'file')
		fprintf('RUNNING DILATION\n');
		script = fullfile(Repo_path, 'Scripts', 'binary_dilation.py');
        cmd = sprintf('"%s" "%s" --subj %s --input_path "%s"', pyExe, script, subject, out_dir);
    	system(cmd);
    	fprintf('Executed command: %s\n', cmd);
	end

```

## `binary_dilation.py`  					   

- Running the ```binary_dilation``` script requires the following dependencies:
  - Python: 3.9.21
  - NumPy: 1.23
  - NiBabel: 5.1
  - SciPy: 1.10
  - scikit-image: 0.20

### Code Block for `binary_dilation.py`

```python
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
```

![](https://github.com/user-attachments/assets/732cf8e4-8321-4034-ae6b-d503bcfa7b0f)

***

## Fix_Cerebellum_SUIT.m Block IV: Derive Corrected Mask 

- The final corrected RR is generated by crossing the SUIT-based mask with the original RR using fslmaths. This step is performed to eliminate any oversegmentation into the meninges/non-cerebellar tissue. 
- The participant's PET image is pre-processed and linearly registered to its T1-weighted MRI using FSL-FLIRT (6 degrees of freedom and mutualinfo cost function flag). 
- The transformation matrix obtained is inverted and applied to bring the corrected reference region into PET space (linear interpolation, thresholding at 0.5, followed by binarization). 
- Once in PET space, the mean reference region signal is extracted using fslstats. 

```matlab
% STEP IV: DERIVE CORRECTED MASK
%__________________________________________________________________________
	
    %%%%%%%%%------T1--SPACE---------%%%%%%%%%%%
    
    % Intersection mask between transformed SUIT and cerebellum mask
    
    intersection_mask   = fullfile(suitMainOutputsPath, sprintf('%s_aparc+aseg_native_ref_cerebellum-whole_bin-CORRECTED.nii.gz', subject)); 
    
    if exist(original_cereb_mask, 'file')
    	    fprintf('Found file for original cerebellum: %s\n', original_cereb_mask);
    	else
    		fprintf('Source file for original cerebellum mask not found: %s\n', original_cereb_mask);
    		return;
	end
    
    if ~exist(intersection_mask, 'file')
    	fsl_command = sprintf('%s/fslmaths %s -mul %s/maskSUIT_warp_2_%s_native_T1_dilated.nii -bin %s', ...
        	fslpath, original_cereb_mask, suitDerivativesPath, subject, intersection_mask);
        	
		fprintf('\nExecuting command: %s\n', fsl_command);
    	[status, result] = system(fsl_command);

    	if status == 0
    		fprintf('\n');
        	fprintf('T1-space Intersection mask created successfully: %s\n', intersection_mask);
    	else
    		fprintf('\n');
        	fprintf('Error creating intersection mask: %s\n', result);
    	end
    	
    end
```

***

## Fix_Cerebellum_SUIT.m Block IV: Coreg of Corrected Mask to PET Space

- The participant's PET image is pre-processed and linearly registered to its T1-weighted MRI using FSL-FLIRT (6 degrees of freedom and mutualinfo cost function flag). 
- The transformation matrix obtained is inverted and applied to bring the corrected reference region into PET space (linear interpolation, thresholding at 0.5, followed by binarization). 
- Once in PET space, the mean reference region signal is extracted using fslstats (Script 16).


```matlab
	%%%%%%%%%------PET--SPACE---------%%%%%%%%%%%
	
	coreg_pet = fullfile(suitMainOutputsPath, sprintf('%s_ref_pet-CORRECTED.nii.gz', subject)); 
    
	Coreg_Corrected_RR_to_PET_script = '/PATH_TO_DATA/PET/SUIT_Subscripts/4_Coreg_Corrected_RR_to_PET.sh';

	if ~exist(coreg_pet, 'file') 
    	cmd = sprintf('%s %s', Coreg_Corrected_RR_to_PET_script, subject);
    	status = system(cmd);
    
    	if status ~= 0
    		fprintf('\n');
        	error('Coreg_Corrected_RR_to_PET.sh failed: %s', cmd);
        else
        	fprintf('\n');
        	fprintf('Corrected RR registered to PET Space: %s\n', coreg_pet);
    	end
	end

```

### Code Block for `4_Coreg_Corrected_RR_to_PET.sh`

```bash
#!/bin/bash

## ----- Edited by SG 04/18/2025
############

subj=$1 

# SUIT main output directory
DIROUT=/PATH_TO_DATA/PET/amyloidpet/output/${subj}/pet_procd/RR_Rescue/SUIT_Main_Outputs

#####################################################################  Ref to PET

PET_OUT=/PATH_TO_DATA/PET/amyloidpet/output/${subj}/pet_procd
FSLFLIRT=/usr/local/fsl-5.0.9/bin/flirt
FSLMATHS=/usr/local/fsl-5.0.9/bin/fslmaths
FSLSTATS=/usr/local/fsl-5.0.9/bin/fslstats 

#------------------------------------------------------------------
#REGISTER CORRECTED REFERENCE REGION TO PET SPACE
if [ ! -f ${DIROUT}/${subj}_ref_pet-CORRECTED.nii.gz ]; then
echo "STAGE 9A: REGISTER ${subj} REFERENCE REGION FROM MRI SPACE TO PET SPACE"
cmd="${FSLFLIRT} \
     -in ${DIROUT}/${subj}_aparc+aseg_native_ref_cerebellum-whole_bin-CORRECTED.nii.gz \
     -ref ${PET_OUT}/smoothed_${subj}_PET_mean_1_5.nii \
     -applyxfm -init ${PET_OUT}/${subj}_mritoPET.xfm \
     -out ${DIROUT}/${subj}_aparc+aseg_PET_ref_cerebellum-whole-CORRECTED.nii.gz \
      -datatype float"
eval ${cmd}
echo -e "STAGE 9A: REGISTRATION OF REFERENCE REGION DONE]]\r\n Command --> ${cmd}\r\n"

#BINARIZE EXTRACTED REFERENCE REGION
echo -e "\nSTAGE 9B: BINARIZE ${subj} REFERENCE REGION"
${FSLMATHS} ${DIROUT}/${subj}_aparc+aseg_PET_ref_cerebellum-whole-CORRECTED.nii.gz -thr 0.5 -bin ${DIROUT}/${subj}_aparc+aseg_PET_ref_cerebellum-whole_bin-CORRECTED.nii.gz

echo "\nSTAGE 9B: BINARIZE REFERENCE REGION DONE"
echo -e "STAGE 9B: BINARIZE REFERENCE REGION]]\r\n Command --> ${cmd}\r\n" 

#MULTIPLY REFERENCE REGION BY PET 
echo "\nSTAGE 9C: MULTIPLY REFERENCE REGION BY PET"
cmd="${FSLMATHS} ${PET_OUT}/smoothed_${subj}_PET_mean_1_5.nii -mul ${DIROUT}/${subj}_aparc+aseg_PET_ref_cerebellum-whole_bin-CORRECTED.nii.gz ${DIROUT}/${subj}_ref_pet-CORRECTED.nii.gz"
eval ${cmd}

echo -e "\nSTAGE 9C: MULTIPLIED REFERENCE REGION BY PET]]\r\n Command --> ${cmd}\r\n" 
fi
``` 
- On registering the corrected mask to PET space, you should be able to overlay the pre/post-correction masks and visualize the difference.

![](https://github.com/user-attachments/assets/e4879343-31fe-4137-a999-95c58169a17e)
	

***

# References
- Landau, S., Ward, T. J., Murphy, A., & Jagust, W. Flortaucipir (AV-1451) processing methods.https://adni.bitbucket.io/reference/docs/UCBERKELEYAV1451/ UCBERKELEY_AV1451_Methods_2021-01-14.pdf
- Diedrichsen, J., A spatially unbiased atlas template of the human cerebellum. Neuroimage, 2006. 33(1): p. 127-38.
- Tustison, N.J., Cook, P.A., Holbrook, A.J. et al. The ANTsX ecosystem for quantitative biological and medical imaging. Sci Rep 11, 9068 (2021). https://doi.org/10.1038/ s41598-021-87564-6
