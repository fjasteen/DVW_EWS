# src/riparias_download.R

library(curl)
library(readr)
library(dplyr)
library(sf)
library(stringr)
library(rgbif)
library(leaflet)

# 1. WFS-CSV downloaden met curl
url <- "https://alert.riparias.be/api/wfs/observations?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=observation&OUTPUTFORMAT=csv"
tempfile_csv <- tempfile(fileext = ".csv")

h <- new_handle()
handle_setopt(h, noprogress = FALSE, progressfunction = function(down, up, total_down, total_up) {
  cat(sprintf("\rGedownload: %.2f MB", down / 1024 / 1024))
  flush.console()
  TRUE
})

tryCatch({
  curl_download(url, destfile = tempfile_csv, mode = "wb", handle = h)
  cat("\nDownload voltooid.\n")
  
  size_mb <- file.info(tempfile_csv)$size / 1024 / 1024
  cat(sprintf("Bestandsgrootte: %.2f MB\n", size_mb))
  if (size_mb < 5) warning("Bestand is mogelijk onvolledig.")
}, error = function(e) {
  stop("Download mislukt: ", e$message)
})

# 2. CSV lezen en coördinaten extraheren
EWS_WFS <- read_csv(tempfile_csv, show_col_types = FALSE) %>%
  mutate(
    coords = str_remove(location, "^SRID=3857;POINT\\("),
    coords = str_remove(coords, "\\)$"),
    x = as.numeric(str_extract(coords, "^[^ ]+")),
    y = as.numeric(str_extract(coords, "[^ ]+$"))
  ) %>%
  filter(!is.na(x) & !is.na(y))

# 3. GBIF-checklist ophalen
checklist <- name_lookup(datasetKey = "23e95da2-6095-4778-b893-9af18a310cb6")
species_keys <- checklist$data %>%
  filter(!rank %in% c("KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS")) %>%
  pull(nubKey) %>%
  unique()

EWS_WFS_spec <- EWS_WFS %>%
  filter(species_gbif_key %in% species_keys)

# 4. Naar sf object in Lambert 72
EWS_WFS_spec_sf <- st_as_sf(EWS_WFS_spec, coords = c("x", "y"), crs = 3857) %>%
  st_transform(31370)

# 5. Inlezen shapefiles uit data/input/
input_path <- "./data/input"
dvw_indeling <- st_read(file.path(input_path, "DVW_indeling.gpkg")) %>% st_transform(31370)
dvw_percelen <- st_read(file.path(input_path, "DVW_percelen.gpkg")) %>% st_transform(31370)

# 6. Intersecties
EWS_kern <- st_filter(EWS_WFS_spec_sf, dvw_indeling)
EWS_percelen <- st_filter(EWS_WFS_spec_sf, dvw_percelen)

# 7. Export
output_path <- "data/output"
dir.create(output_path, showWarnings = FALSE, recursive = TRUE)

st_write(EWS_kern, file.path(output_path, "EWS_kern.gpkg"), layer = "observaties", delete_dsn = TRUE)
st_write(EWS_percelen, file.path(output_path, "EWS_percelen.gpkg"), layer = "observaties", delete_dsn = TRUE)

# 8. Visualisatie (optioneel)
layers <- list(
  EWS_kern = EWS_kern,
  EWS_percelen = EWS_percelen,
  dvw_indeling = dvw_indeling,
  dvw_percelen = dvw_percelen
)
layers_wgs <- lapply(layers, st_transform, crs = 4326)

leaflet() %>%
  addProviderTiles("CartoDB.Positron") %>%
  addPolygons(data = layers_wgs$dvw_indeling, color = "#999999", weight = 1, fillOpacity = 0.2, group = "DVW Indeling") %>%
  addPolygons(data = layers_wgs$dvw_percelen, color = "#666666", weight = 1, fillOpacity = 0.2, group = "DVW Percelen") %>%
  addCircleMarkers(data = layers_wgs$EWS_kern, radius = 4, stroke = FALSE, fillColor = "#3182bd", fillOpacity = 0.7, group = "EWS Kern") %>%
  addCircleMarkers(data = layers_wgs$EWS_percelen, radius = 4, stroke = TRUE, color = "#e41a1c", weight = 1, fillOpacity = 1, group = "EWS Percelen") %>%
  addLayersControl(
    overlayGroups = c("EWS Percelen", "EWS Kern", "DVW Indeling", "DVW Percelen"),
    options = layersControlOptions(collapsed = FALSE)
  )
