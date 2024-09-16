# Date Created: 8/16/2024
# Version Number: v1
# Date Modified: 
# Modifications:
# ************************************************************** #
# ~~~~~~~  ERA5 Re-Analysis Raster Processing Step 1      ~~~~~~~ #
# ************************************************************** #
#   Adapted from scripts developed by Keith Spangler, Muskaan Khemani for 
#       processing raster data onto polygon boundaries:
#       https://github.com/Climate-CAFE/population_weighting_raster_data/blob/main/Population_Weighting_Raster_to_Census_Units.R
#     
## Purpose: Process ERA5 rasters to administrative boundaries. This
##    script is the first in a two-step raster processing process. In this 
##    a grid-based polygon will be derived from the raster grid of ERA5 data.
##    An example is provided for Kenya data.
##    
## Overall Processing Steps:
##    Script: 02_Aggregate_ERA5_Kenya_SetFishnet_v1.R
## 1) Create Fishnet that can be used to extract ERA5 data from raster stack
##    including ERA5 hourly data (this file). 
##    This will allow for extraction from raster stack  
##    without the large computational burden of a terra::zonal loop (as below)
##
##    Script: 03_Aggregate_ERA5_Kenya_UseFishnet_v1.R
## 2) Load administrative boundaries
## 3) Create extraction points from the union of the block and fishnet. These 
##    are what we can use to extract values from the raster that overlaps with
##    with the points aligning to each block (next file).
## 4) Estimate the ward-level exposure to ERA5, accounting for the availability
##    of data within the block (next file).

##### Need to install the latest version of packages using install.packages() to meet version requirement

library("terra")  # For raster data
library("sf")     # For vector data
library("plyr")
library("doBy")
library("tidyverse")
library("tidycensus")
library("lwgeom")

sf_use_s2(FALSE)  
# S2 is for computing distances, areas, etc. on a SPHERE (using
# geographic coordinates, i.e., lat/lon in decimal-degrees); no need for this
# extra computational processing time if using PROJECTED coordinates,
# since these are already mapped to a flat surface. Here, ERA5 data
# is indeed in geographic coordinates, but the scale of areas we are 
# interested in is very small, and hence the error introduced by 
# ignoring the Earth's curvature over these tiny areas is negligible and
# a reasonable trade off given the dramatic reduction in processing time. Moreover,
# the areas we calculate are not an integral part of the process
# and any error in that step would not materially impact the final output

# Check package version numbers
#
if (packageVersion("terra") < "1.5.34"   | packageVersion("sf") < "1.0.7" | 
    packageVersion("plyr")  < "1.8.7"    | packageVersion("lwgeom") < "0.2.8" | 
    packageVersion("doBy")  < "4.6.19"   | packageVersion("tidyverse") < "1.3.1") {
  cat("WARNING: packages are outdated and may result in errors.") }

# %%%%%%%%%%%%%%%%%%%%%%% USER-DEFINED PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%% #
# Set up directories to read in and output data
#

era_dir <- "YOUR LOCAL PATH TO DOWNLOADED .NC FILES"


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%%%%%%%%%% CREATE ERA5 EXTRACTION POINTS  %%%%%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
#
# %%%%%%%%%%%%%%%%%%%%%%%%% READ IN THE ERA5 RASTER DATA %%%%%%%%%%%%%%%%%%%%% #
#
era_files <- list.files(era_dir, pattern=paste0('.*.nc'), full.names = F)

# Stack all of the hourly files by year
#
era_files <- paste0(era_dir, "/", era_files)
era_stack <- rast(era_files)

# %%%%%%%%%%%%%%%%%%%% CREATE A FISHNET GRID OF THE RASTER EXTENT %%%%%%%%%%%% #
#
# Here, we are making a shapefile that is a fishnet grid of the raster extent.
# It will essentially be a polygon of lines surrounding each ERA5 cell.
#
# Reference/credit: https://gis.stackexchange.com/a/243585
#
era_raster <- era_stack[[1]]
era_extent <- ext(era_raster)
xmin <- era_extent[1]
xmax <- era_extent[2]
ymin <- era_extent[3]
ymax <- era_extent[4]

era_matrix <- matrix(c(xmin, ymax,
                        xmax, ymax,
                        xmax, ymin,
                        xmin, ymin,
                        xmin, ymax), byrow = TRUE, ncol = 2) %>%
  list() %>% 
  st_polygon() %>% 
  st_sfc(., crs = st_crs(era_raster))

# Create fishnet of the ERA5 matrix. This takes some time.
#
era_rows <- dim(era_raster)[1]
era_cols <- dim(era_raster)[2]
era_fishnet <- st_make_grid(era_matrix, n = c(era_cols, era_rows), 
                             crs = st_crs(era_raster), what = 'polygons') %>%
  st_sf('geometry' = ., data.frame('ID' = 1:length(.)))

# Write fishnet to output for use in later scripts
#
st_write(era_fishnet, paste0(era_dir, "/", "era_fishnet.shp"), append = FALSE)

# Automated QC check -- confirm same coordinate reference system (CRS) between
#                       the fishnet and ERA5 raster
if ( !(all.equal(st_crs(era_raster), st_crs(era_fishnet))) ) {
  cat("ERROR: CRS's do not match \n") } else { cat(":) CRS's match \n") }
