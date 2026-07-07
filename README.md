### Amyloid-PET Reference Region Rescue Pipeline

- **How we derive our reference region**: The whole cerebellum is designated as the reference region (RR) for [18F] Florbetaben (FBB) amyloid-PET processing. Generation of this RR is performed by thresholding the Desikan Killany atlas using Freesurfer defined labels corresponding to bilateral cerebellar gray and white matter. 
- **Problems -- Segmentation Errors**: At times, the FBB RR may encroach into the tentorium, the falx cerebri, or the lateral meninges, allowing for off-target binding to contaminate the estimated signal. 
- **Fix**: Here, we describe a protocol that utilizes the SUIT  toolbox and template (spatially unbiased atlas template of the cerebellum and brainstem; http://www.diedrichsenlab.org/imaging/suit.htm)  to automatically correct for oversegmentation of the RR mask generated through FreeSurfer. 

![](https://github.com/user-attachments/assets/10dd9a7f-e0a9-4b0b-a980-8d5e98c2daac)

***Figure***: Reference region mask correction showing over-segmentation into the inferior bone (top panel), bilateral meninges (middle), and the falx cerebri (lower panel)

***

### Testing Summary:
- To ensure this correction method would not systematically alter the signal from the reference region in participants who had the correction applied compared with those who didn’t, we ran the pipeline on a set of 100 subjects who had originally passed reference region quality control. Post-correction, the global standardized uptake value ratio (SUVR) was highly correlated with the original SUVR (R² = 0.99), with a mean change of 0.01 (0.90%). 
- To visualize the correction, we applied this method to a sample of 100 previously-failed participants and computed the difference between their original and corrected masks. A group-level map showed that the correction primarily eliminated oversegmentation around the lateral meninges.

![](https://github.com/user-attachments/assets/5cb8c03a-8718-48f2-8b84-9ea2738ab789)

Cite as: Ganesan S., Lee N, Hand M, Tennant V, Braskie MN. HABS-HD Reference Region Rescue Pipeline - [18F] Florbetaben (FBB) Amyloid PET for HABS-HD. Revised 4/08/26. Accessible via the Laboratory of Neuro Imaging (LONI) Imaging Data Archive: https://ida.loni.usc.edu

***
