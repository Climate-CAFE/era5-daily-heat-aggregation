# Date Created: 8/16/2024
# Version Number: v1
# Date Modified: 
# Modifications:
# ************************************************************** #
# ~~~~~  ERA5 Re-Analysis Raster Processing Step 2        ~~~~~~ #
# ************************************************************** #
#   Adapted from scripts developed by Keith Spangler, Muskaan Khemani for 
#       processing raster data onto polygon boundaries:
#       https://github.com/Climate-CAFE/population_weighting_raster_data/blob/main/Population_Weighting_Raster_to_Census_Units.R
#     
## Purpose: Process ERA5 rasters to Kenya administrative boundaries (wards). This
##    script is the first in a two-step raster processing process. In this 
##    a grid-based polygon will be derived from the raster grid of ERA5 data.
##    
## Overall Processing Steps:
##    Script: 02_Aggregate_ERA5_Kenya_SetFishnet_v1.R
## 1) Create Fishnet that can be used to extract ERA5 data from raster stack
##    including ERA5 hourly data (this file). 
##    This will allow for extraction from raster stack  
##    without the large computational burden of a terra::zonal loop (as below)
##
##    Script: 03_Aggregate_ERA5_Kenya_UseFishnet_v1.R
## 2) In this file, we will join the fishnet, which is a polygon grid with lines 
##    surrounding the grid of the ERA5 raster with the Ward geometries that have
##    been queried from the Database of Global Administrative Boundaries
##    (gadm.org). In merging the polygon grid with the ward polygon data, 
##    we ensure that every ward will be aligned with the relevant
##    ERA5 temperature metrics for the area.
## 3) Create extraction points from the union of the wards and fishnet. These 
##    are what we can use to extract values from the raster that overlaps with
##    with the points aligning to each wards (this file).
## 4) Estimate the ward-level exposure to ERA5, accounting for the availability
##    of data within the wards (this file).

##### Need to install the latest version of packages using install.packages() to meet version requirement

library("terra")  # For raster data
library("sf")     # For vector data
library("plyr")   # For data management
library("doBy")   # For aggregation of data across groups
library("tidyverse") # For data management
library("lwgeom")
library("weathermetrics")

sf_use_s2(FALSE) 
# S2 is for computing distances, areas, etc. on a SPHERE (using
# geographic coordinates, i.e., lat/lon in decimal-degrees); no need for this
# extra computational processing time if using PROJECTED coordinates,
# since these are already mapped to a flat surface. Here, pm25
# is indeed in geographic coordinates, but the scale of areas we are 
# interested in is very small, and hence the error introduced by 
# ignoring the Earth's curvature over these tiny areas is negligible and
# a reasonable trade off given the dramatic reduction in processing time. Moreover,
# the areas we calculate are not an integral part of the process
# and any error in that step would not materially impact the final output

# Check package version numbers
#
if (packageVersion("terra") < "1.5.34"   | packageVersion("sf") < "1.0.7" | 
    packageVersion("plyr")  < "1.8.7"    |
    packageVersion("doBy")  < "4.6.19"   | packageVersion("lwgeom") < "0.2.8") {
  cat("WARNING: packages are outdated and may result in errors.") }

# Set up directories to read in and output data
#

era_dir <- "YOUR LOCAL PATH TO CREATED FISHNET SHAPE FILE"
geo_dir <- "YOUR LOCAL PATH"
outdir <- "YOUR LOCAL PATH"

use_fishnet <- function(countryName, wardFileName, ahead) {

  country_wards <- st_read(paste0(geo_dir, "/", wardFileName))

  # Read in the fishnet created previously
  #
  era_fishnet <- st_read(paste0(era_dir, "/", "era_fishnet.shp"))

  # Match the CRS of the wards shapefile to the fishnet and era data and confirm match
  #
  country_wards <- st_transform(country_wards, crs = st_crs(era_fishnet))

  # Run check to ensure CRS are equal
  #
  if (!isTRUE(all.equal(st_crs(country_wards), st_crs(era_fishnet)))) {
    cat("ERROR: CRS's don't match \n")  } else { cat(":) CRS's match \n") }

  # %%%%%%%%%%%%%%%%%% CREATE UNION BETWEEN FISHNET AND WARDS %%%%%%%%% #
  # Reference/credit: https://stackoverflow.com/a/68713743
  #
  my_union <- function(a,b) {
    st_agr(a) = "constant"
    st_agr(b) = "constant"
    op1 <- st_difference(a, st_union(b))
    op2 <- st_difference(b, st_union(a))
    op3 <- st_intersection(b, a)
    union <- rbind.fill(op1, op2, op3)
    return(st_as_sf(union))
  }

  # Ensure geometries are valid
  #
  country_wards <- st_make_valid(country_wards) 
  era_fishnet <- st_make_valid(era_fishnet)

  # Create the union between the fishnet and blocks layers
  #
  fishnetward <- my_union(era_fishnet, country_wards)
  fishnetward$UniqueID <- 1:dim(fishnetward)[1]

  # Automated QC -- Check to see if the union has introduced any geometry errors
  #                 and fix as appropriate
  #
  check <- try(st_make_valid(fishnetward), silent = TRUE)

  if (class(check)[1] == "try-error") {
  
    cat("There is an issue with the sf object \n")
    cat("..... Attempting fix \n")
  
    geo_types <- unique(as.character(st_geometry_type(fishnetward, by_geometry = TRUE)))
  
    cat("..... Geometry types in sf object 'fishnetward':", geo_types, "\n")
  
    for (j in 1:length(geo_types)) {
      fishnetward_subset <- fishnetward[which(st_geometry_type(fishnetward, by_geometry = TRUE) == geo_types[j]),]
      if (j == 1) { updated_fishnetward <- fishnetward_subset; next }
      updated_fishnetward <- rbind(updated_fishnetward, fishnetward_subset)
    
    }
  
    check2 <- try(st_make_valid(updated_fishnetward), silent = TRUE)
  
    if (class(check2)[1] == "try-error") {
      cat("..... ERROR NOT RESOLVED \n") } else {
        cat("..... :) issue has been fixed! \n")
      
        updated_fishnetward <- updated_fishnetward[order(updated_fishnetward$UniqueID),]
        if ( !(all.equal(updated_fishnetward$UniqueID, fishnetward$UniqueID)) ) {
          cat("ERROR: Unique IDs do not match \n") } else {
            cat(":) unique ID's match. Reassigning 'updated_fishnetward' to 'fishnetward' \n")
            fishnetward <- updated_fishnetward    
          }
      }
  }

  # Automated QC check -- ensure that there is a variable identifying the geographies
  #                       that will be used for aggregation (here Kenya wards). 
  #                       Note that these variable names may change
  #                       depending on the version and country used. 
  #
  geo_id_var <- names(fishnetward)[grep("^GID_3", names(fishnetward), ignore.case = TRUE)]

  # Identify the polygons of the fishnet that do not intersect with the ward
  # data; drop them.
  #
  before_dim <- dim(fishnetward)[1]
  fishnetward <- fishnetward[which( !(is.na(fishnetward[[geo_id_var]])) ),]
  after_dim <- dim(fishnetward)[1]

  cat("Dropped", before_dim - after_dim, "polygons that do not intersect with census data \n")

  # Some polygons formed in the union are incredibly small -- this adds unnecessary
  # computation time without materially reducing error. Drop the small polygons.
  # NOTE: Typically, when calculating areas of polygons, you would want to convert to
  #       a projected CRS appropriate for your study domain. For the purpose of identifying
  #       negligibly small areas to drop here, the error introduced by using geographic
  #       coordinates for calculating area at this scale is negligible.
  #
  fishnetward$Area_m2 <- as.numeric(st_area(fishnetward))

  fishnetward <- fishnetward[which(fishnetward$Area_m2 > 10),]

  # %%%%%%%%%%%%%%%%%%%%%%%%%%%% CONVERT POLYGON TO POINTS %%%%%%%%%%%%%%%%%%%%% #
  #
  # The final step is to create the extraction points. This is a point shapefile
  # that will enable us to extract ERA5 data from an entire stack of rasters rather
  # than individually processing zonal statistics on each raster layer. 
  #
  # NOTE: This step throws a warning message related to using geographic coordinates 
  #       rather than a projected CRS. This step is only placing a point inside the 
  #       polygon to identify which ERA5 grid cell we need to extract from; as all
  #       of the input data are on the same CRS and the spatial scale of the polygons
  #       is extremely small, this does not introduce substantive error.
  #
  extraction_pts <- st_point_on_surface(fishnetward)

  # %%%%%%%%%%%%%%%%%%%%% CALCULATE LAND-AREA WEIGHTED AVG BY WARD %%%%%%%%%%%% #
  
  # Get the total area by ward to calculate the spatial weight value (typically 1.0)
  #
  eqn <- as.formula(paste0("Area_m2 ~ ", geo_id_var))

  # Define a function to calculate sums such that if all values are NA then it returns
  # NA rather than 0.
  #
  sumfun <- function(x) { return(ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))) }
  
  # Calculate the sum area by ward
  #
  ptstotal <- summaryBy(eqn, data = as.data.frame(extraction_pts), FUN = sumfun)
  
  # Merge area and calculate spatial weight of points
  #
  extraction_pts <- merge(extraction_pts, ptstotal, by = geo_id_var, all.x = TRUE)
  extraction_pts$SpatWt <- extraction_pts$Area_m2 / extraction_pts$Area_m2.sumfun
  
  # Convert the extraction_pts to a SpatVector object
  #
  extraction_pts <- terra::vect(extraction_pts)

  # %%%%%%%%%%%%%%%%%%%%%% EXTRACT ERA5 VALUES FOR EACH WARD POINT %%%%%%%%%%%% #
  # 
  # In this step, we will use the extraction points to extract the ERA5 grid cell
  # underlying each portion of a geography (ward) across the entire raster stack of values.
  #
  # This process is set to run as a loop by year to cut down the size of the 
  # file that will be produced by the processing. For each year, and in using 
  # a cluster computing environment, the processing takes about 20 minutes and uses
  # about 15GB of R memory on a computing cluster. 
  
  # This can be further reduced by running as a loop for
  # each month. The hourly data are transformed to a long format for processing of daily
  # summary measures, and included the full 20+ year period would lead to a 
  # very large dataframe (1400 polygons * 365 days * 24 hours * X years)
  #
  # %%%%%%%%%%%%%%%%%%%%%%%%%%% READ IN THE ERA5 RASTER DATA %%%%%%%%%%%%%%%%%% #
  #
  era_files <- list.files(era_dir, pattern=paste0('.*.nc'), full.names = F)
  
  # Humidex function from heatmetrics package:
  # Reference: K.R. Spangler, S. Liang, and G.A. Wellenius. "Wet-Bulb Globe 
  # Temperature, Universal Thermal Climate Index, and Other Heat Metrics for US 
  # Counties, 2000-2020." Scientific Data (2022). doi: 10.1038/s41597-022-01405-3
  #
  # Lawrence, M. G. The relationship between relative humidity and the dewpoint 
  # temperature in moist air - A simple conversion and applications. B. Am. 
  # Meteorol. Soc. 86, 225–233, https://doi.org/10.1175/Bams-86-2-225 (2005).
  #
  humidex <- function(t, td) {
    hx <- (t + (5/9) * ((6.1094 * exp((17.625 * td) / (243.04 + td))) - 10))
    return(hx)
  }

  # Set year to process
  #
  years_to_agg <- c(2000:2023)

  for (year in c(years_to_agg)) {
  
    cat("Now processing ", year, "\n")
  
    # Subset to year from all files 
    #
  
    if (ahead==TRUE) {
      era_files_yr <- era_files[substr(era_files, 12, 15) == year |
                              substr(era_files, 12, 15) == year - 1]
    }  
    else {
      era_files_yr <- era_files[substr(era_files, 12, 15) == year |
                                substr(era_files, 12, 15) == year + 1]
    }
  
    # Stack all of the daily files by year
    #
    era_files_yr <- paste0(era_dir, "/", era_files_yr)
    era_stack <- rast(era_files_yr)
    
    # Reset times to align with Kenya time zones
    #
    ####################
    # CODE CANNOT WORK #
    ####################
    
    terra::time(era_stack) <- with_tz(terra::time(era_stack) , tzone = "Africa/Nairobi")
    
    # Subset stack to exclude the times that run past specified year due to 
    # time zone adjustment, and to exclude the previous year that was read in 
    # for time zone adjustment
    #
    era_stack <- subset(era_stack, time(era_stack) < date(paste0(year + 1, "-01-01")) &
                          time(era_stack) >= date(paste0(year, "-01-01")))
    
    ####################
    # CODE CANNOT WORK #
    ####################
    
    # Our ERA stack includes three variables (2m dew point temperature,
    # skin temperature, and 2m temperature). Create subsets to perform
    # daily aggregation on
    #
    dewpoint_names <- names(era_stack)[grepl("d2m", names(era_stack))]
    temp2m_names <- names(era_stack)[grepl("t2m", names(era_stack))]
    skin_temp_names <- names(era_stack)[grepl("skt", names(era_stack))]
    
    # Subset raster to each measure and convert Kelvin to Celsius
    #
    era_stack_d2m <- subset(era_stack, names(era_stack) %in% dewpoint_names) - 273.15
    era_stack_t2m <- subset(era_stack, names(era_stack) %in% temp2m_names) - 273.15
    era_stack_skt <- subset(era_stack, names(era_stack) %in% skin_temp_names) - 273.15
    
    # Apply the heat index function to the SpatRaster objects
    #
    era_stack_hti <- xapp(era_stack_t2m, era_stack_d2m, fun = function(temp, dewpoint) {
      heat.index(t = temp, dp = dewpoint,
                 temperature.metric = "celsius",
                 output.metric = "celsius", round = 6)
    })
    
    # Apply the humidex function to the SpatRaster objects
    #
    era_stack_hum <- xapp(era_stack_t2m, era_stack_d2m, fun = function(temp, dewpoint) {
      humidex(t = temp, td = dewpoint)
    })
    
    # Assign names and times to new layers
    #
    names(era_stack_hti) <- paste0("hti", substr(names(era_stack_hti), 4, 10))
    names(era_stack_hum) <- paste0("hum", substr(names(era_stack_hum), 4, 10))
    
    ####################
    # CODE CANNOT WORK #
    ####################
    
    terra::time(era_stack_hti) <- terra::time(era_stack_d2m)
    terra::time(era_stack_hum) <- terra::time(era_stack_d2m)
    
    ####################
    # CODE CANNOT WORK #
    ####################
    
    # Confirm all layers are same length
    #
    if (nlyr(era_stack_d2m) == nlyr(era_stack_t2m) & 
        nlyr(era_stack_d2m) == nlyr(era_stack_skt) &
        nlyr(era_stack_d2m) == nlyr(era_stack_hti) &
        nlyr(era_stack_d2m) == nlyr(era_stack_hum)) {
      layer_n <- nlyr(era_stack_d2m)
      cat("Same number of layers in all stacks\n")
    } else {
      cat("Different number of layers, assess whether timing is consistent\n")
      break
    }
    
    # Create a time sequence starting from January first of the year date
    #
    
    ##### Unknown tz="EAT" ? 
    
    start_date <- as.POSIXct(paste0(year, "-01-01 00:00"), tz = "EAT")
    time_seq <- seq(from = start_date, by = "hour", length.out = layer_n)
    
    # Convert our time sequence to a factor format. This will allow for use as 
    # a grouping variable in assessing daily level summary measures
    #
    daily_factor <- as.factor(as.Date(time_seq))
    
    # Set list of rasters. We will do the same processing of daily minimum, mean,
    # and maximum for the three variables we queried through ERA5, so we set
    # the lasters in a list and conduct the processing as below
    #
    list_rasters <- list(era_stack_d2m, era_stack_t2m, era_stack_skt, era_stack_hti, era_stack_hum)
    
    for (i in 1:length(list_rasters)) {
      
      # Tracker for viewing progress
      #
      cat("Now processing raster ", i, "\n")
      
      # Aggregate to daily mean temperature
      #
      daily_mean <- tapp(list_rasters[[i]], daily_factor, fun = mean)
      
      # Aggregate to daily maximum temperature
      #
      daily_max <- tapp(list_rasters[[i]], daily_factor, fun = max)
      
      # Aggregate to daily minimum temperature
      #
      daily_min <- tapp(list_rasters[[i]], daily_factor, fun = min)
      
      # Project points to WGS84 (coordinate system for ERA stack)
      #
      extraction_pts <- project(extraction_pts, crs(list_rasters[[i]]))
      
      # Extract daily summaries to point-based grid
      #
      mean_pts <- terra::extract(daily_mean, extraction_pts)
      max_pts <- terra::extract(daily_max, extraction_pts)
      min_pts <- terra::extract(daily_min, extraction_pts)
      
      # Join results with extraction points (includes geographic identifiers)
      #
      mean_pts <- cbind(extraction_pts, mean_pts)
      max_pts <- cbind(extraction_pts, max_pts)
      min_pts <- cbind(extraction_pts, min_pts)
      
      # Use package sf to join points on coast and not covered by ERA5 land to
      # nearby temperature measures
      #
      mean_pts_sf <- st_as_sf(mean_pts)
      max_pts_sf <- st_as_sf(max_pts)
      min_pts_sf <- st_as_sf(min_pts)
      
      # Identify a date in year to assess missingness for points outside
      # land extent
      #
      if (ahead==TRUE) {
        varname <- paste0("X", year, ".01.01")
      }
      else {
        varname <- paste0("X", year+1, ".01.01")
      }
      
      # Subset missing data
      #
      mean_pts_missing <- mean_pts_sf[is.na(mean_pts_sf[[varname]]), ]
      max_pts_missing <- max_pts_sf[is.na(max_pts_sf[[varname]]), ]
      min_pts_missing <- min_pts_sf[is.na(min_pts_sf[[varname]]), ]
      
      # Subset available data
      #
      mean_pts_avail <- mean_pts_sf[!is.na(mean_pts_sf[[varname]]), ]
      max_pts_avail <- max_pts_sf[!is.na(max_pts_sf[[varname]]), ]
      min_pts_avail <- min_pts_sf[!is.na(min_pts_sf[[varname]]), ]
      
      # Join these with nearest features with available temp data
      #
      names_temp <- names(mean_pts_avail)[!names(mean_pts_avail) %in% names(extraction_pts)]
      
      mean_pts_missing_join <- mean_pts_missing[c(names(extraction_pts))]
      mean_pts_avail_join <- mean_pts_avail[c(names_temp)]
      
      mean_pts_missing <- st_join(mean_pts_missing_join, mean_pts_avail_join, join = st_nearest_feature)
      
      max_pts_missing_join <- max_pts_missing[c(names(extraction_pts))]
      max_pts_avail_join <- max_pts_avail[c(names_temp)]
      
      max_pts_missing <- st_join(max_pts_missing_join, max_pts_avail_join, join = st_nearest_feature)
      
      min_pts_missing_join <- min_pts_missing[c(names(extraction_pts))]
      min_pts_avail_join <- min_pts_avail[c(names_temp)]
      
      min_pts_missing <- st_join(min_pts_missing_join, min_pts_avail_join, join = st_nearest_feature)
      
      # Rejoin updated data with those already including temp
      #
      mean_pts <- rbind(mean_pts_avail, mean_pts_missing)
      max_pts <- rbind(max_pts_avail, max_pts_missing)
      min_pts <- rbind(min_pts_avail, min_pts_missing)
      
      # Convert the extracted data to a data frame
      #
      mean_pts_df <- as.data.frame(mean_pts)
      max_pts_df <- as.data.frame(max_pts)
      min_pts_df <- as.data.frame(min_pts)
      
      # Remove geometry column
      #
      mean_pts_df$geometry <- NULL
      max_pts_df$geometry <- NULL
      min_pts_df$geometry <- NULL
      
      # Extract columns relevant to ERA5 data
      #
      era5_cols <- names(mean_pts_df)[!names(mean_pts_df) %in% c("ID.1", names(extraction_pts))]
      
      # Set names for ERA5 variables based on input raster naming
      #
      mean_name <- paste0(substr(names(list_rasters[[i]])[1], 1, 3), "_mean")
      max_name <- paste0(substr(names(list_rasters[[i]])[1], 1, 3), "_max")
      min_name <- paste0(substr(names(list_rasters[[i]])[1], 1, 3), "_min")
      
      # Transpose the data frame to get time series format (long-form)
      #
      mean_long <- mean_pts_df %>%
        pivot_longer(cols = all_of(era5_cols), names_to = "date", values_to = mean_name) 
      
      max_long <- max_pts_df %>%
        pivot_longer(cols = all_of(era5_cols), names_to = "date", values_to = max_name) %>%
        select(UniqueID, date, !!sym(max_name))
      
      min_long <- min_pts_df %>%
        pivot_longer(cols = all_of(era5_cols), names_to = "date", values_to = min_name) %>%
        select(UniqueID, date, !!sym(min_name))
      
      # Combine data into single dataframe
      #
      era5_long <- left_join(mean_long, max_long, by = c("UniqueID", "date")) %>%
        left_join(., min_long, by = c("UniqueID", "date"))
      
      # Save data as date format
      #
      era5_long$date <- as.Date(substr(era5_long$date, 2, 11), format = "%Y.%m.%d")
      
      # Join together all measures
      #
      if (i == 1) {
        era5_full <- era5_long
      } else if ( i != 1 ) {
        era5_long <- era5_long[c("UniqueID", "date", mean_name, max_name, min_name)]
        era5_full <- left_join(era5_full, era5_long, by = c("UniqueID", "date"))
      }
      
    }
    
    # In this step, we will use the extraction points to extract the ERA5 grid cell
    # underlying each portion of a ward across the entire raster stack of values.
    # We again will follow the same process for each individual variable, and use 
    # a loop to conduct the processing
    #
    varnames <- names(era5_full)[!names(era5_full) %in% c(names(extraction_pts), "date", "ID.1")]
    
    for (i in 1:length(varnames)) {
      
      cat("Now processing ", varnames[i], "\n")
      
      # Before we calculate the final weighted average of the ERA5 measure, we need to check for missing data.
      # If a value is NA on one of the polygons, then it will give an underestimate of the
      # temperature since the weights will no longer add to 1. Example: there are two
      # polygons, each with 50% area. If Tmax is 30 C in one and NA in the other, then
      # the area weighted average (which removes NA values) would give: (30 * 0.5) + (NA * 0.5) = 15 C.
      # Therefore, we need to re-weight the weights based on the availability of data.
      #
      eqn <- as.formula(paste0("SpatWt ~ GID_3 + date")) 
      avail <- summaryBy(eqn,
                         data = era5_full[which( !(is.na(era5_full[[varnames[i]]])) ),],
                         FUN = sumfun)
      
      # Merge this value back into the longform ERA5 data
      #
      era5_full <- merge(era5_full, avail, by = c("GID_3", "date"), all.x = TRUE)
      
      # Re-weight the area weight by dividing by total available weight
      #
      era5_full$SpatWt <- era5_full$SpatWt / era5_full$SpatWt.sumfun
      
      # QC: check that the weights of *available data* all add to 1
      #
      eqn <- as.formula(paste0("SpatWt ~ GID_3 + date"))
      check <- summaryBy(eqn,
                         data = era5_full[which( !(is.na(era5_full[[varnames[i]]])) ),],
                         FUN = sumfun)
      
      if (length(which(round(check$SpatWt.sumfun, 4) != 1)) > 0) {
        cat("ERROR: weights do not sum to 1", "\n"); break 
      } else {
        cat(":) weights sum to 1", "\n")
        era5_full$SpatWt.sumfun <- NULL
      }
      
      # Multiply the variable of interest (here "newvarname") by the weighting value and then
      # sum up the resultant values within admin boundaries. This is an area-weighted average.
      #
      tempvar <- paste0(varnames[i], "_Wt")
      era5_full[[tempvar]] <- era5_full[[varnames[i]]] * era5_full[["SpatWt"]]
      
      eqn <- as.formula(paste0(tempvar, " ~ GID_3 + date")) 
      
      final <- summaryBy(eqn, data = era5_full, FUN = sumfun)
      
      # Automated QC to confirm that the dimensions are correct
      #
      if ( length(unique(extraction_pts$GID_3))  * length(unique(era5_full$date)) != dim(final)[1]) {
        cat("ERROR: incorrect dimensions of final df", "\n"); break
      } else { cat(":) dimensions of final df are as expected", "\n") }
      
      # Set name for output
      #
      names(final)[grep(paste0("^", varnames[i]), names(final))] <- varnames[i]
      
      head(final)
      
      if (i == 1) {
        finaloutput <- final
      } else {
        finaloutput <- left_join(finaloutput, final, by = c("GID_3", "date"))
      }
      
    }
    
    cat("The final output has", dim(finaloutput)[1], "rows. \n")
    cat("The first few lines of the output are: \n")
    print(head(finaloutput))
    
    # Automated QC: missing data
    #
    missing_t2m_max <- which(is.na(finaloutput$t2m_mean))
    missing_t2m_min <- which(is.na(finaloutput$t2m_min))
    missing_t2m_mea <- which(is.na(finaloutput$t2m_max))
    missing_d2m_max <- which(is.na(finaloutput$d2m_mean))
    missing_d2m_min <- which(is.na(finaloutput$d2m_min))
    missing_d2m_mea <- which(is.na(finaloutput$d2m_max))
    missing_skt_max <- which(is.na(finaloutput$skt_mean))
    missing_skt_min <- which(is.na(finaloutput$skt_min))
    missing_skt_mea <- which(is.na(finaloutput$skt_max))
    missing_hti_max <- which(is.na(finaloutput$hti_mean))
    missing_hti_min <- which(is.na(finaloutput$hti_min))
    missing_hti_mea <- which(is.na(finaloutput$hti_max))
    missing_hum_max <- which(is.na(finaloutput$hum_mean))
    missing_hum_min <- which(is.na(finaloutput$hum_min))
    missing_hum_mea <- which(is.na(finaloutput$hum_max))
    
    if (length(missing_t2m_max) > 0 | length(missing_d2m_max) > 0 | length(missing_skt_max) > 0
        | length(missing_hti_max) > 0 | length(missing_hum_max) > 0) {
      cat("WARNING: Note the number of missing ward-days by variable: \n")
      cat("Dew Max:", length(missing_t2m_max), "\n")
      cat("Temp Max:", length(missing_d2m_max), "\n")
      cat("Skin Temp Max:", length(missing_skt_max), "\n")
      cat("Heat Index:", length(missing_hti_max), "\n")
      cat("Humidex:", length(missing_hum_max), "\n")
      
      cat("The first few lines of missing T2M_max (if any) are printed below: \n")
      print(head(finaloutput[missing_t2m_max,]))
      
      cat("The first few lines of missing D2M_max (if any) are printed below: \n")
      print(head(finaloutput[missing_d2m_max,]))
      
      cat("The first few lines of missing SKT_max (if any) are printed below: \n")
      print(head(finaloutput[missing_skt_max,]))
      
      cat("The first few lines of missing HTI_max (if any) are printed below: \n")
      print(head(finaloutput[missing_hti_max,]))
      
      cat("The first few lines of missing HUM_max (if any) are printed below: \n")
      print(head(finaloutput[missing_hum_max,]))
      
    } else { cat(":) No missing temperature values! \n") }
    
    # Automated QC: impossible temperature values
    #
    num_temp_errors_t2m <- length(which(finaloutput$t2m_max < finaloutput$t2m_mean |
                                          finaloutput$t2m_max < finaloutput$t2m_min |
                                          finaloutput$t2m_min > finaloutput$t2m_mean |
                                          finaloutput$t2m_min > finaloutput$t2m_max))
    
    num_temp_errors_d2m <- length(which(finaloutput$d2m_max < finaloutput$d2m_mean |
                                          finaloutput$d2m_max < finaloutput$d2m_min |
                                          finaloutput$d2m_min > finaloutput$d2m_mean |
                                          finaloutput$d2m_min > finaloutput$d2m_max))
    
    num_temp_errors_skt <- length(which(finaloutput$skt_max < finaloutput$skt_mean |
                                          finaloutput$skt_max < finaloutput$skt_min |
                                          finaloutput$skt_min > finaloutput$skt_mean |
                                          finaloutput$skt_min > finaloutput$skt_max))
    
    num_temp_errors_hti <- length(which(finaloutput$hti_max < finaloutput$hti_mean |
                                          finaloutput$hti_max < finaloutput$hti_min |
                                          finaloutput$hti_min > finaloutput$hti_mean |
                                          finaloutput$hti_min > finaloutput$hti_max))
    
    num_temp_errors_hum <- length(which(finaloutput$hum_max < finaloutput$hum_mean |
                                          finaloutput$hum_max < finaloutput$hum_min |
                                          finaloutput$hum_min > finaloutput$hum_mean |
                                          finaloutput$hum_min > finaloutput$hum_max))
    
    
    if (num_temp_errors_t2m > 0 | num_temp_errors_d2m > 0 | num_temp_errors_skt > 0 |
        num_temp_errors_hti > 0  | num_temp_errors_hum > 0) { 
      
      print("ERROR: impossible temperature values. Applicable rows printed below:")
      print(finaloutput[which(finaloutput$t2m_max < finaloutput$t2m_mean |
                                finaloutput$t2m_max < finaloutput$t2m_min |
                                finaloutput$t2m_min > finaloutput$t2m_mean |
                                finaloutput$t2m_min > finaloutput$t2m_max),])
      print(finaloutput[which(finaloutput$d2m_max < finaloutput$d2m_mean |
                                finaloutput$d2m_max < finaloutput$d2m_min |
                                finaloutput$d2m_min > finaloutput$d2m_mean |
                                finaloutput$d2m_min > finaloutput$d2m_max),])
      print(finaloutput[which(finaloutput$skt_max < finaloutput$skt_mean |
                                finaloutput$skt_max < finaloutput$skt_min |
                                finaloutput$skt_min > finaloutput$skt_mean |
                                finaloutput$skt_min > finaloutput$skt_max),])
      print(finaloutput[which(finaloutput$hti_max < finaloutput$hti_mean |
                                finaloutput$hti_max < finaloutput$hti_min |
                                finaloutput$hti_min > finaloutput$hti_mean |
                                finaloutput$hti_min > finaloutput$hti_max),])
      print(finaloutput[which(finaloutput$hum_max < finaloutput$hum_mean |
                                finaloutput$hum_max < finaloutput$hum_min |
                                finaloutput$hum_min > finaloutput$hum_mean |
                                finaloutput$hum_min > finaloutput$hum_max),])
      
    } else { print(":) all temperature values are of correct *relative* magnitude") }
    
    # Output results by year to output directory
    #
    saveRDS(finaloutput, paste0(outdir, "/", countryName, "_agg_era5_", year, "_d2m_t2m_skt_hti_hum.rds"))
    
  }
}

# %%%%%%%%%%%%%%%%%%%%%% LOAD WARDS SHAPEFILE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
#
# Download wards shapefile
#

##### Go to https://gadm.org/download_country.html, download the targeted country's shapefile,
##### put level-3 shapefiles in geo_dir. Must put all level-3 shapefiles in 
##### that folder. Cannot just put a single .shp file in it. 

##### Call the defined function
##### Argument "ahead" is ture when the targeted country's local time is ahead of UTC time. Otherwise, it is false. 
use_fishnet("Kenya", "gadm41_KEN_3.shp", TRUE)