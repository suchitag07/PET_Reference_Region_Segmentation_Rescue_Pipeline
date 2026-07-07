function Fix_Cerebellum_SUIT(Repo_path, spm12_path, antspath, fslpath, pyExe, subject_in, original_cereb_mask, out_dir)
%
% Wriiten by SG - 04/16/2025
%__________________________________________________________________________
%
%  Main outputs: Corrected RR mask here ${subject_id}/SUIT_Main_Outputs
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
    
% STEP I: ISOLATE SEG 
%__________________________________________________________________________

    Source = fullfile(suitDerivativesPath, sprintf('%s_N4_ACPC.nii', subject));
    seg = fullfile(suitDerivativesPath, sprintf('c_%s_N4_ACPC_pcereb.nii', subject));  % T1 space mask -> output of seg step
    if ~exist(seg, 'file')
        suit_isolate_seg({Source});
    end
	
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
    
    diary off;
    
%% DONE
%__________________________________________________________________________  
