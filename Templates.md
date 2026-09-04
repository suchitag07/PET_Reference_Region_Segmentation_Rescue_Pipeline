# Required Templates

This pipeline depends on two externally maintained templates
that are not redistributed here, since both carry their own
license terms. Download them once and point the pipeline at
them via the variables described below.

## 1. SUIT cerebellar template and mask

Files: `Cerebellum-SUIT.nii.gz`, `maskSUIT.nii`

These ship with the SUIT toolbox, which this pipeline already
requires. Download the toolbox and install it into
`spm12/toolbox/suit/`:
https://www.diedrichsenlab.org/imaging/suit_download.htm

License: Creative Commons Attribution-NonCommercial 3.0
Unported (CC BY-NC 3.0). Free for non-commercial use with
attribution.

Cite:
- Diedrichsen, J. (2006). A spatially unbiased atlas template
  of the human cerebellum. NeuroImage, 33(1), 127-138.
- Diedrichsen, J., Balsters, J. H., Flavell, J., Cussans, E.,
  & Ramnani, N. (2009). A probabilistic atlas of the human
  cerebellum. NeuroImage, 46(1), 39-46.

## 2. MNI ICBM152 nonlinear asymmetric 2009c T1

File: `mni_icbm152_t1_tal_nlin_asym_09c.nii`

Used as the fixed image for ACPC alignment in `SUIT_Prep.sh`.
Download the ICBM 2009c Nonlinear Asymmetric package:
https://nist.mni.mcgill.ca/icbm-152-nonlinear-atlases-2009/

Copyright (C) 1993-2004 Louis Collins, McConnell Brain Imaging
Centre, Montreal Neurological Institute, McGill University.
Permission to use, copy, modify, and distribute is granted
provided the copyright notice appears in all copies. Provided
"as is" without warranty.

Cite:
- Fonov, V. S., Evans, A. C., Botteron, K., Almli, C. R.,
  McKinstry, R. C., Collins, D. L., & BDCG (2011). Unbiased
  average age-appropriate atlases for pediatric studies.
  NeuroImage, 54(1), 313-327.

## Where to put them

Create a `Templates/` directory at the repo root and place the MNI template inside it. The `SUIT_Prep.sh` script will fetch the template from this directory and utilize it to run ANTS registration (bring the subject T1 to MNI/ACPC aligned space - which is required before `Fix_Cerebellum_SUIT` can run.) 
