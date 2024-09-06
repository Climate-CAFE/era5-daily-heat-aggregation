# Date Created: 8/16/2024
# Version Number: v1
# Date Modified: 
# Modifications:
# Overview:
#     This code uses the ecmwfr R package to download ERA5 temperature measures
#     from The Copernicus Climate Data Store. More details on the ERA5 API
#     access using the ecmwfr R package are accessible at:
#         https://github.com/bluegreen-labs/ecmwfr
#     Please explore the vignettes provided and note the provided instructions
#     for how to sign up for a Copernicus account and to access the relevant
#     user and key inputs below required to query data.
#
# Load required packages
#

##### Need to install the latest version of packages using install.packages() to meet version requirement

library("ecmwfr")
library("sf")

# Check package version numbers
#
if (packageVersion("ecmwfr") < "1.5.0"   | packageVersion("sf") < "1.0.16" ) {
  cat("WARNING: packages are outdated and may result in errors.") }

# Set directory. Establishing this at the start of the script is useful in case
# future adjustments are made to the path. There are subdirectories within this
# directory for reading in Global Administrative boundaries and for outputting
# the ERA5 rasters queried in this script.
#
ecmw_dir <- "YOUR LOCAL PATH"

my_download <- function(countryName, gpkgFileName, timeGap=0) {
  
  ##### Need to first create a subfolder "country_GADM" on your path, and put .gpkg file 
  ##### you downloaded into this subfolder.

  country_folder <- paste0(countryName, '_', 'GADM')
  country <- st_read(paste0(ecmw_dir, '/', country_folder, "/", gpkgFileName), layer = "ADM_ADM_0")

  # Assess bounding box. The bounding box represents the coordinates of the 
  # extent of the shapefile, and will be used to specify the area we would like
  # to query from Copernicus Climate Data Store. The API will allow any bounding 
  # parameters; however, values that deviate from the original model grid scale
  # will be interpolated onto a new grid. Therefore, it’s recommended that for 
  # ERA5-Land (which is 0.1˚ resolution) the bounding coordinates be divisible by 
  # 0.1 (e.g., 49.5˚N, -66.8˚E, etc.), and that coordinates for ERA5 be divisible
  # by 0.25 (e.g., 49.25˚N, -66.75˚E, etc.)
  #
  country_bbox <- st_bbox(country)

  # Add a small buffer around the bounding box to ensure the whole region 
  # is queried, and round the parameters to a 0.1 resolution. A 0.1 resolution
  # is applied because the resolution of netCDF ERA5 data is .25x.25
  # https://confluence.ecmwf.int/display/CKB/ERA5%3A+What+is+the+spatial+reference
  #
  country_bbox$xmin <- round(country_bbox$xmin[[1]], digits = 1) - 0.1
  country_bbox$ymin <- round(country_bbox$ymin[[1]], digits = 1) - 0.1
  country_bbox$xmax <- round(country_bbox$xmax[[1]], digits = 1) + 0.1
  country_bbox$ymax <- round(country_bbox$ymax[[1]], digits = 1) + 0.1

  # The ERA5 area query requires the area to be formatted specifically as below,
  # with slashes separating the longitude and latitude of inputs. 
  #
  query_area <- paste0(country_bbox$ymax, "/", country_bbox$xmin, "/",
                     country_bbox$ymin, "/", country_bbox$xmax)

  # The set of inputs below specify the range of years to request, and set four
  # cut points throughout the year with which API requests will be cut. There is 
  # a limit on the data size that can be downloaded in a given request, so we 
  # cut each year to four requests of three months each to ensure the request
  # is completed.
  #
  query_starts <- c("01-01", "04-01", "07-01", "10-01")
  query_ends <- c("03-31", "6-30", "9-30", "12-31")
  query_years <- c(2000:2023)

  # Use for loop to query in 3 month blocks, by year
  #
  for (yr in query_years) {
  
    # Track progress
    #
    cat("Now processing year ", yr, "\n")
  
    # For each year, the query is divided into 3-month sections. If a request is
    # too large, it will not be accepted by the CDS servers, so this division
    # of requests is required
    #
    for (i in 1:4) {
    
      # Track progress
      #
      cat("Now processing quarter ", i, "\n")
    
      # Extract inputs for start and end based on list of dates at begin and 
      # end of months around quarter
      #
      query_1 <- query_starts[i]
      query_2 <- query_ends[i]
    
      # Establish query for date periods. This formats the date inputs
      # as they need to be formatted.
      #
      query_dates <- paste0(yr, "-", query_1, "/", yr, "-", query_2)
    
      # The below is the formatted API request language. All of the inputs
      # specified below in proper formatting can be identified by forming a 
      # request using the Copernicus CDS point-and-click interface for data
      # requests. https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land?tab=form
      # Select the variables, timing, and netcdf as the output format, and then 
      # select "Show API Request" at the bottom of the screen. 
      #
      # Note that the target is the filename that will be exported to the path
      # specified in the next part of the script. If using a loop, ensure that
      # that the unique features of each request are noted in the output.
      #
      request_era <- list(
        "dataset_short_name" = "reanalysis-era5-land",
        "product_type" = "reanalysis",
        "variable" = c("2m_dewpoint_temperature", "2m_temperature", "skin_temperature"),
        "date" = query_dates,
        "time" = c('00:00', '01:00', '02:00',
                  '03:00', '04:00', '05:00',
                  '06:00', '07:00', '08:00',
                  '09:00', '10:00', '11:00',
                  '12:00', '13:00', '14:00',
                  '15:00', '16:00', '17:00',
                  '18:00', '19:00', '20:00',
                  '21:00', '22:00', '23:00'),
        "area" = query_area, # as bounding box: ymax/xmin/ymin/xmax latmax/lonmin/lonmin/lonmax
        "format" = "netcdf",
        "target" = paste0("era5-", countryName, "-", yr , "_", query_1, "_", query_2, ".nc")
      )
    
      # Submit Request
      #
      req_country <- wf_request(
        user = "YOUR USER ID",   # user ID (for authentification)
        request  = request_era,  # the request
        transfer = TRUE,     # download the file
        path     = paste0(ecmw_dir, "/", countryName, "_", "ERA5_Out/")    ##### Need to create "ERA5_Out" subfolder on your path 
                                                                          # store data in current working directory
      )
    
    }
  }


  # The ERA5 data is distributed in UTC. We want to calculate our daily measures
  # based on the targeted country's local time. For example, we will query the last three 
  # hours of 1999 as Kenya is 3 hours ahead of UTC
  #
  timeVector = c('00:00', '01:00', '02:00',
                 '03:00', '04:00', '05:00',
                 '06:00', '07:00', '08:00',
                 '09:00', '10:00', '11:00',
                 '12:00', '13:00', '14:00',
                 '15:00', '16:00', '17:00',
                 '18:00', '19:00', '20:00',
                 '21:00', '22:00', '23:00')
  
  if (timeGap > 0) {
    date = "1999-12-31"
    time = tail(timeVector, n=timeGap)
  }
  else {
    date = "2024-01-01"
    time = timeVector[1: -timeGap]
  }
  
  request_era_timeGap <- list(
    "dataset_short_name" = "reanalysis-era5-land",
    "product_type" = "reanalysis",
    "variable" = c("2m_dewpoint_temperature", "2m_temperature", "skin_temperature"),
    "date" = date,
    "time" = time,
    "area" = query_area, # as bounding box: ymax/xmin/ymin/xmax latmax/lonmin/lonmin/lonmax
    "format" = "netcdf",
    "target" = paste0("era5-", countryName, "-", date, ".nc")
  )

  # Submit Request
  #
  req_country <- wf_request(
    user = "YOUR USER ID",   # user ID (for authentification)
    request  = request_era_timeGap,  # the request
    transfer = TRUE,     # download the file
    path = paste0(ecmw_dir, "/", countryName, "_", "ERA5_Out/")   ##### Need to create "ERA5_Out" subfolder on your path
                                                                  # store data in current working directory
  )

}

# Set key for web API. See the *Use: Copernicus Climate Data Store (CDS)* heading
# in the GitHub linked above for details on accessing these parameters. Note:
# your user ID and API key should never be shared externally.
#

##### Do these steps:
##### 1. Create an ECMWF account by self-registering. Follow https://github.com/bluegreen-labs/ecmwfr?tab=readme-ov-file
##### under section "Use: ECMWF Data Store services".
##### 2. Visit user profile to get user ID and key. Follow https://github.com/bluegreen-labs/ecmwfr?tab=readme-ov-file
##### under section "Use: ECMWF Data Store services".
##### 3. Visit user profile to accept the terms and conditions in the profile page. 
##### 4. Go to ERA-5 land page following https://github.com/bluegreen-labs/ecmwfr?tab=readme-ov-file
##### under section "Data Requests". Go to "Terms of use" block to accept the data licence to use products.
##### 5. Visit user profile page again to double check that Dataset licences to use Copernicus products shows up there and 
##### has been accepted. 

##### You can also only put key in this function. It will find the corresponding USER ID internally.

wf_set_key(user = "YOUR USER ID", key = "YOUR PERSONAL ACCESS TOKEN")

# Download targeted country's boundaries geopackage. These data were downloaded from GADM
# https://gadm.org/download_country.html. The layer specification "ADM_ADM_0"
# indicates that the level 0 boundaries should be read in, representing the 
# national boundary. We read in the boundaries here to establish the geographic
# extent that should be queried from ERA5, so ward-level boundaries are not 
# needed.
#

#### Call the defined function
my_download("Kenya", "gadm41_KEN.gpkg", timeGap=3)
