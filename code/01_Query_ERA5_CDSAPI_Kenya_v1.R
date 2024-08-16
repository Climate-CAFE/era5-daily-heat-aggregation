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
ecmw_dir <- ""

# Set key for web API. See the *Use: Copernicus Climate Data Store (CDS)* heading
# in the GitHub linked above for details on accessing these parameters. Note:
# your user ID and API key should never be shared externally.
#
wf_set_key(service = "cds", user = "", key = "")

# Read in Kenya boundaries geopackage. These data were downloaded from GADM
# https://gadm.org/download_country.html. The layer specification "ADM_ADM_0"
# indicates that the level 0 boundaries should be read in, representing the 
# national boundary. We read in the boundaries here to establish the geographic
# extent that should be queried from ERA5, so ward-level boundaries are not 
# needed.
#
kenya <- st_read(paste0(ecmw_dir, "Kenya_GADM/gadm41_KEN.gpkg"), layer = "ADM_ADM_0")

# Assess bounding box. The bounding box represents the coordinates of the 
# extent of the shapefile, and will be used to specify the area we would like
# to query from Copernicus Climate Data Store. The API will allow any bounding 
# parameters; however, values that deviate from the original model grid scale
# will be interpolated onto a new grid. Therefore, it’s recommended that for 
# ERA5-Land (which is 0.1˚ resolution) the bounding coordinates be divisible by 
# 0.1 (e.g., 49.5˚N, -66.8˚E, etc.), and that coordinates for ERA5 be divisible
# by 0.25 (e.g., 49.25˚N, -66.75˚E, etc.)
#
kenya_bbox <- st_bbox(kenya)

# Add a small buffer around the bounding box to ensure the whole region 
# is queried, and round the parameters to a 0.1 resolution. A 0.1 resolution
# is applied because the resolution of netCDF ERA5 data is .25x.25
# https://confluence.ecmwf.int/display/CKB/ERA5%3A+What+is+the+spatial+reference
#
kenya_bbox$xmin <- round(kenya_bbox$xmin[[1]], digits = 1) - 0.1
kenya_bbox$ymin <- round(kenya_bbox$ymin[[1]], digits = 1) - 0.1
kenya_bbox$xmax <- round(kenya_bbox$xmax[[1]], digits = 1) + 0.1
kenya_bbox$ymax <- round(kenya_bbox$ymax[[1]], digits = 1) + 0.1

# The ERA5 area query requires the area to be formatted specifically as below,
# with slashes separating the longitude and latitude of inputs. 
#
query_area <- paste0(kenya_bbox$ymax, "/", kenya_bbox$xmin, "/",
                     kenya_bbox$ymin, "/", kenya_bbox$xmax)

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
      "target" = paste0("era5-kenya-",yr , "_", query_1, "_", query_2,".nc")
    )
    
    # Submit Request
    #
    req_kenya <- wf_request(
      user     = "<add_user_id>",   # user ID (for authentification)
      request  = request_era,  # the request
      transfer = TRUE,     # download the file
      path     = paste0(ecmw_dir, "ERA5_Out/")       # store data in current working directory
    )
    
  }
}


# The ERA5 data is distributed in UTC. We want to calculate our daily measures
# based on Kenya local time. To accomodate this, we will query the last three 
# hours of 1999 as Kenya is 3 hours ahead of UTC
#
request_era_1999 <- list(
  "dataset_short_name" = "reanalysis-era5-land",
  "product_type" = "reanalysis",
  "variable" = c("2m_dewpoint_temperature", "2m_temperature", "skin_temperature"),
  "date" = "1999-12-31",
  "time" = c('21:00', '22:00', '23:00'),
  "area" = query_area, # as bounding box: ymax/xmin/ymin/xmax latmax/lonmin/lonmin/lonmax
  "format" = "netcdf",
  "target" = paste0("era5-kenya-1999_12-31.nc")
)

# Submit Request
#
req_kenya <- wf_request(
  user     = "<add_user_id>",   # user ID (for authentification)
  request  = request_era_1999,  # the request
  transfer = TRUE,     # download the file
  path     = paste0(ecmw_dir, "ERA5_Out/")         # store data in current working directory
)
