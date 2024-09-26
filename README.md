# Query of Hourly ERA5-Land Data and Aggregation of Daily Summary Heat Metrics
## Project Overview
Using the R ecmwfr package, ERA5-Land hourly temperature measures are downloaded from the Copernicus Climate Data Store (CDS). Heat index and humidex metrics are derived from ERA5-Land hourly 2-meter temperature and 2-meter dew point temperature. Daily mean, maximum, and minimum measures are assessed across administrative boundaries for 2-meter temperature, 2-meter dew point temperature, skin temperature, heat index and humidex. Kenya is used as a demonstration area for the Copernicus CDS API query and spatial aggregation, using administrative boundaries from the Database of Global Administrative Areas.

### Why Use ERA5?
When selecting a dataset for analysis of the relationship between climate change and health, there are several primary considerations. They include:
- **Temporal Resolution**: Depending on your question of interest, hourly, daily, or annual summary metrics could be most appropriate. ERA5 has a very high temporal resolution available in their hourly product. This allows for computation of measures for daily minimums, means, and maximums, as has been done here.
- **Time Span**: Selecting a data resource is also informed by the time span available. Some research questions require an extensive historical data record spanning far into the past, and other times the most recent data is more pertinent. ERA5-Land provides data spanning back to 1950, and data for the recent past as well.
- **Spatial Resolution**: Re-analysis data such as ERA5 use a combination of various inputs to derive estimates of temperature at a finer scale and across greater areas than individual weather stations could provide. Different data sources provide differing resolution, with some datasets sharing temperature and other metrics at 1m x 1m grids, and others at much larger scales. ERA5-Land provides data with 9km x 9km grids, which is relatively large. This larger grid size can be advantageous, in that the storage and processing of less spatially resolved data will be far less intensive.
- **Spatial Extent**: One of the key advantages for ERA5 is its global spatial extent. As opposed to country-specific datasets, like the Parameter-elevation Regressions on Independent Slopes Model (PRISM) data for the US, ERA5 is global in its extent. 
- **Reliability**: Whatever your research question is, you should ensure the dataset you opt to use is reliable. ERA products have been [widely used in global climate assessments](https://rmets.onlinelibrary.wiley.com/doi/full/10.1002/qj.3803) by organizations including WHO and the IPCC. Previous work has been conducted to compare the ERA5 outputs to available global monitoring data across different [climate regions](https://ieeexplore.ieee.org/stamp/stamp.jsp?arnumber=9658540), [across Europe](https://www.mdpi.com/2073-4441/14/4/543), in [East Africa](https://www.mdpi.com/2073-4433/11/9/996), as well as other regions across the globe. Further assessing whether ERA5 has been tested for reliability in your study region of interest can help inform possible limitations with respect to specific regions, measures, or other data elements.

### Why These Heat Metrics?
This repository provides code for analyzing three distinct metrics from ERA5 (2-m temperature, 2-m dew point temperature, skin temperature) and two derived metrics (heat index and humidex). 

## Usage
This repository provides the building blocks for the query of any data from the Copernicus CDS. Code for spatial aggregation of ERA5-Land hourly netCDF files from their native raster format to daily measures averaged across administrative boundaries are also included, using the terra and sf packages. These spatial aggregation methods can be used to derive measures from ERA5-Land in analysis of sociodemographic disparities or epidemiologic studies of temperature and health outcomes. An additional script is provided with some example applications of R package ggplot2 to visualize temperature spatially and over time.

Comments are included within the code repository with descriptions of how to manipulate the ERA5 API language to query additional variables, time frames, or spatial extents. Please note that users will need to set up an account with the Copernicus CDS for the API query to function effectively. For more information on the ecmwfr package and details about how to set up an account and access the necessary user ID and API key inputs for the API query please see: https://github.com/bluegreen-labs/ecmwfr
## Data Sources
- [ERA5-Land hourly data from 1950 to present](https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land)
- [Database of Global Administrative Areas](https://gadm.org/)
## Workflow
Four scripts are included in the code repository.
1) 01_Query_ERA5_CDSAPI_Kenya_v1.R applies the ecmwfr package to query hourly ERA5-Land data from the Copernicus CDS using the ecmwfr package.
   - The necessary code to set your API key in your R environment is provided, as well as a description of the necessary inputs for an effective API query, including the dataset, spatial extent, time frame, and variables requested.
   - The query is broken down into queries for data every three months. A for loop is used to query these three-month data cuts across the 24-year period of the full dataset. These cuts were set as the Copernicus CDS API restricts the amount of data accessible in a single pull.
   - *Please Note*: The API query can be time-consuming and the resulting output can be extremely large if the API query is not correctly specified. When first using the API for a new use case, consider requesting only a few hours or days of data for a small spatial area in order to get an estimate for the time and data size that will be queried with larger sets.
2) 02_Aggregate_ERA5_Kenya_SetFishnet_v1.R is the first in a two-step process for aggregating the queried rasters to the administrative boundaries.
   - A fishnet approach is used, where a grid of points is established and the merged with points representing the spatial extent of the administrative boundaries for the area of interest.
   - This is set as a separate file because it can be very time consuming with a highly spatially resolved raster. The ERA5-Land dataset is shared at a 9 km grid resolution, so this runs quickly in this application.
   - More details about the use of a fishnet for spatial aggregation of raster data can be found here: [https://github.com/Climate-CAFE/population_weighting_raster_data](https://github.com/Climate-CAFE/population_weighting_raster_data)
3) 03_Aggregate_ERA5_Kenya_UseFishnet_v1.R uses the fishnet grid set up in script 2, and merges the grid with centroids for the administrative boundaries in Kenya.
   - The raster data time series is reset from Coordinated Universal Time (UTC) to East Africa Time (EAT).
   - Hourly heat index and humidex are estimated from the 2-m temperature and 2-m dew point temperature.
   - Daily mean, minimum, and maximum are assessed across the raster, and then joined to the extraction points (the union of the fishnet grid and adminstrative centroids).
   - Spatially weighted averages across the administrative boundaries are computed from the extraction points.
   - The resulting output is a dataframe with Kenya administrative boundaries and a time series of daily mean, minimum, and maximum for 2-m temperature, 2-m dew point temperature, skin temperature, heat index, and humidex.
## Dependencies
Packages used in this repository include:
- library("ecmwfr")         for era5 data query
- library("terra")          for raster data
- library("sf")             for vector data
- library("plyr")           for data management
- library("doBy")           for aggregation of data across groups
- library("tidyverse")      for data management
- library("lwgeom")         for spatial data management
- library("weathermetrics") for heat index estimation
## References
Humidex estimation references:
- K.R. Spangler, S. Liang, and G.A. Wellenius. "Wet-Bulb Globe Temperature, Universal Thermal Climate Index, and Other Heat Metrics for US Counties, 2000-2020." Scientific Data (2022). doi: 10.1038/s41597-022-01405-3
- Lawrence, M. G. The relationship between relative humidity and the dewpoint temperature in moist air - A simple conversion and applications. B. Am. Meteorol. Soc. 86, 225–233, https://doi.org/10.1175/Bams-86-2-225 (2005).

Heat index (weathermetrics package) reference:
- Anderson GB, Bell ML, Peng RD. 2013. Methods to calculate the heat index as an exposure metric in environmental health research. Environmental Health Perspectives 121(10):1111-1119.

ECMWFR package reference:
- Hufkens, K., R. Stauffer, & E. Campitelli. (2019). ecmwfr: Programmatic interface to the two European Centre for Medium-Range Weather Forecasts API services. Zenodo. http://doi.org/10.5281/zenodo.2647531.
