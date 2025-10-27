#######################################################
# Download GBIF occurrences for DVW priority species
# Date: Sys.Date()
# 
# Dit script downloadt GBIF-occurrence-data voor België 
# voor alle soorten op de DVW-checklist (inclusief 
# Zizania latifolia). De resultaten worden opgeslagen,
# uitgepakt, geanalyseerd en vergeleken met vorige 
# downloads. Nieuwe waarnemingen worden gelabeld.
# Upload a file .Renviron in project folder with
# GBIF_USER=je_gebruikersnaam
# GBIF_PWD=je_wachtwoord
# GBIF_EMAIL=je_email@adres.com
#######################################################

# ------------------------------------------------------------------
# 0. Controleer en installeer ontbrekende libraries (fallback)
# ------------------------------------------------------------------
required_packages <- c("tidyverse", "here", "rgbif", "lubridate", "sf", "leaflet")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(paste("Package", pkg, "niet gevonden. Installeren..."))
    install.packages(pkg, repos = "https://cloud.r-project.org", type="binary")
  }
}

library(tidyverse)      # Data manipulatie (dplyr, readr, etc.)
library(here)           # Makkelijk werken met relatieve paden
library(rgbif)          # Communicatie met de GBIF API
library(lubridate)      # Datums en tijden
library(sf)             # Ruimtelijke objecten
library(dplyr)          # Data bewerkingen

# ------------------------------------------------------------------
# 1. Definieer query parameters
# ------------------------------------------------------------------

# DVW-checklist dataset key op GBIF
datasetKey <- "23e95da2-6095-4778-b893-9af18a310cb6"

# Ophalen van de checklist vanuit GBIF
DVW_list <- name_usage(datasetKey = datasetKey)

# Filter enkel soorten met 'SOURCE' als oorsprong
species_list <- DVW_list$data %>%
  filter(origin == "SOURCE")

# Voeg de soort Zizania latifolia manueel toe
Zizania <- name_backbone("Zizania latifolia")

# Combineer alle species keys
species_keys <- species_list$nubKey %>%
  append(Zizania$speciesKey)

# Alleen records met coördinaten in België vanaf 2013
hasCoordinate <- TRUE
countries <- c("BE")

# ------------------------------------------------------------------
# 2. Start GBIF download request
# ------------------------------------------------------------------

gbif_download_key <- occ_download(
  pred_in("taxonKey", species_keys),             # Soorten
  pred("country", "BE"),                         # Land
  pred_gte("year", 2013),                        # Vanaf 2013
  pred("hasCoordinate", hasCoordinate),          # Alleen met coördinaten
  pred("occurrenceStatus", "present"),           # Alleen aanwezige observaties
  format = "SIMPLE_CSV",                         # Downloadformaat
  user = Sys.getenv("GBIF_USER"),
  pwd = Sys.getenv("GBIF_PWD"),
  email = Sys.getenv("GBIF_EMAIL")
)

# Toon status van het downloadverzoek
metadata <- occ_download_meta(key = gbif_download_key)
cat("Download Key:", metadata$key, "\n")
cat("Download Status:", metadata$status, "\n")

# ------------------------------------------------------------------
# 3. Wacht tot de GBIF download klaar is
# ------------------------------------------------------------------

download_key <- gbif_download_key
output_dir <- here("data", "input", "raw")          # Opslaglocatie
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

max_tries <- 60        # Max aantal keer status checken
interval_sec <- 60     # Interval (seconden) tussen checks

cat("Download gestart voor sleutel:", download_key, "\n")

for (i in 1:max_tries) {
  meta <- occ_download_meta(download_key)
  status <- meta$status
  
  cat("Check", i, "- Status:", status, "\n")
  
  if (status == "SUCCEEDED") {
    cat("Download voltooid. Ophalen gestart...\n")
    break
  } else if (status %in% c("KILLED", "CANCELLED", "FAILED")) {
    stop("Download afgebroken of mislukt: ", status)
  } else {
    Sys.sleep(interval_sec)
  }
  
  if (i == max_tries) stop("Download niet voltooid binnen de voorziene tijd.")
}

# ------------------------------------------------------------------
# 4. Download en unzip het bestand
# ------------------------------------------------------------------

# Geef een consistente bestandsnaam aan de download
dest_file <- file.path(output_dir, paste0("gbif_download_", Sys.Date(), "_", download_key, ".zip"))
occ_download_get(download_key, path = output_dir, overwrite = TRUE)

# Hernoem naar consistente naam
file.rename(file.path(output_dir, paste0(download_key, ".zip")), dest_file)
cat("Download opgeslagen als:", dest_file, "\n")

# Unzip naar map met de download key
unzipped_dir <- file.path(output_dir, download_key)
dir.create(unzipped_dir, showWarnings = FALSE, recursive = TRUE)
unzip(dest_file, exdir = unzipped_dir)
cat("Bestand uitgepakt naar:", unzipped_dir, "\n")

# Verwijder originele ZIP
file.remove(dest_file)
cat("ZIP-bestand verwijderd:", dest_file, "\n")

# ------------------------------------------------------------------
# 5. Lees de GBIF-data in en converteer naar sf
# ------------------------------------------------------------------

# Zoek CSV-bestand in uitgepakte map
csv_file <- list.files(unzipped_dir, pattern = "\\.csv$|occurrence\\.txt$", full.names = TRUE)
if (length(csv_file) == 0) stop("Geen occurrence-bestand gevonden in: ", unzipped_dir)

# Lees de CSV in
gbif_data <- read_tsv(csv_file[1], show_col_types = FALSE)
cat("Ingelezen GBIF-data met", nrow(gbif_data), "records uit:\n", csv_file[1], "\n")

# Filter records zonder coördinaten
gbif_data_clean <- gbif_data %>%
  filter(!is.na(decimalLongitude), !is.na(decimalLatitude))

# Zet om naar sf-object (WGS84)
gbif_sf <- st_as_sf(
  gbif_data_clean,
  coords = c("decimalLongitude", "decimalLatitude"),
  crs = 4326,
  remove = FALSE
)

# Transformeer naar Lambert 72 (EPSG:31370)
gbif_sf_l72 <- st_transform(gbif_sf, 31370)


# ------------------------------------------------------------------
# 6. Laad DVW-shapefiles en maak intersecties
# ------------------------------------------------------------------
input_path <- "./data/input"

# Laad DVW indeling
dvw_indeling <- st_read(file.path(input_path, "DVW_indeling.gpkg")) %>% st_transform(31370)

# Koppel DVW indeling aan data
gbif_sf_l72_indeling <- st_join(gbif_sf_l72, dvw_indeling)

# Laad DVW percelen
dvw_percelen <- st_read(file.path(input_path, "DVW_percelen.gpkg")) %>% st_transform(31370)

# Laad oeverpolygoon
oever_polygoon <- st_read(file.path(input_path,"24 12 Geosfeer Zonder Percelen.shp"))%>% st_transform(31370)

# Selecteer records die binnen de DVW-indeling vallen
idx_kern <- st_intersects(gbif_sf_l72_indeling, dvw_indeling)
EWS_kern <- gbif_sf_l72_indeling[lengths(idx_kern) > 0, ]

# Selecteer records die binnen de DVW-percelen of binnen oeverpolygoon vallen
in_percelen <- lengths(st_intersects(gbif_sf_l72_indeling, dvw_percelen))
in_oever <- lengths(st_intersects(gbif_sf_l72_indeling, oever_polygoon))
idx_totaal <- in_percelen | in_oever                        

EWS_percelen <- gbif_sf_l72_indeling[idx_totaal, ]

# ------------------------------------------------------------------
# 6b. Opruimen raw dataset en schrijf metadata naar logbestand
# ------------------------------------------------------------------

# Verwijder de uitgepakte map (raw data)
if (dir.exists(unzipped_dir)) {
  unlink(unzipped_dir, recursive = TRUE, force = TRUE)
  message("Raw dataset verwijderd: ", unzipped_dir)
}

# Verzamel metadata van de download
meta <- occ_download_meta(download_key)

log_entry <- tibble(
  date = Sys.Date(),
  download_key = download_key,
  doi = meta$doi %||% NA,                   # DOI, indien beschikbaar
  record_count = nrow(gbif_data),           # aantal records in de download
  file = basename(dest_file)
)

# Pad naar de logfolder
output_log_dir <- here("data", "output")
dir.create(output_log_dir, showWarnings = FALSE, recursive = TRUE)

log_file <- file.path(output_log_dir, "gbif_download_log.csv")

# Schrijf of append de log
if (file.exists(log_file)) {
  write_csv(log_entry, log_file, append = TRUE)
} else {
  write_csv(log_entry, log_file)
}

message("Download metadata toegevoegd aan: ", log_file)


# ------------------------------------------------------------------
# 7. Vergelijk met vorige download en label nieuwe records
# ------------------------------------------------------------------

# Zoek de laatst opgeslagen bestanden per type
kern_files <- list.files(output_dir, pattern = "EWS_kern_.*\\.gpkg$", full.names = TRUE)
percelen_files <- list.files(output_dir, pattern = "EWS_percelen_.*\\.gpkg$", full.names = TRUE)

if (length(kern_files) > 0 & length(percelen_files) > 0) {
  message("Vorige datasets gevonden, laad laatste versies in...")
  
  # Laad de laatste versies
  last_kern <- kern_files[which.max(file.mtime(kern_files))]
  last_percelen <- percelen_files[which.max(file.mtime(percelen_files))]
  
  EWS_kern_old <- st_read(last_kern, quiet = TRUE)
  EWS_percelen_old <- st_read(last_percelen, quiet = TRUE)
  
  # Converteer IDs naar character om typefouten te voorkomen
  EWS_kern_old$gbifID <- as.character(EWS_kern_old$gbifID)
  EWS_percelen_old$gbifID <- as.character(EWS_percelen_old$gbifID)
  
  EWS_kern$gbifID <- as.character(EWS_kern$gbifID)
  EWS_percelen$gbifID <- as.character(EWS_percelen$gbifID)
  
  # Label nieuwe records
  EWS_kern$nieuw <- !(EWS_kern$gbifID %in% EWS_kern_old$gbifID)
  EWS_percelen$nieuw <- !(EWS_percelen$gbifID %in% EWS_percelen_old$gbifID)
  
} else {
  message("Geen oude datasets gevonden, markeer alles als nieuw.")
  EWS_kern$nieuw <- TRUE
  EWS_percelen$nieuw <- TRUE
}


# Filter relevante kolommen
col_subset <- c(
  "gbifID",
  "occurrenceID",
  "taxonKey",
  "scientificName",
  "collectionCode",
  "datasetKey",
  "eventDate",
  "individualCount",
  "locality",
  "stateProvince",
  "basisOfRecord",
  "recordedBy",
  "coordinateUncertaintyInMeters",
  "catalogNumber",
  "geometry",
  "AFD",
  "DSTRCT",
  "SCTR"
  "nieuw",
)

EWS_kern <- EWS_kern %>% select(all_of(col_subset))
EWS_percelen <- EWS_percelen %>% select(all_of(col_subset))

# Vernaculaire naam tabel inladen
vernacular_lookup <- read_csv2("./data/input/vernacular_names.csv") %>%
  select(nubKey, vernacularName)

# Voeg vernacularName toe aan beide datasets
EWS_kern <- EWS_kern %>%
  left_join(vernacular_lookup, by = c("taxonKey" = "nubKey")) %>%
  select(all_of(col_subset), vernacularName)

EWS_percelen <- EWS_percelen %>%
  left_join(vernacular_lookup, by = c("taxonKey" = "nubKey")) %>%
  select(all_of(col_subset), vernacularName)

# Sla de huidige versies op (voor de volgende run)
st_write(EWS_kern, file.path(output_dir, paste0("EWS_kern_", Sys.Date(), ".gpkg")), delete_dsn = TRUE)
st_write(EWS_percelen, file.path(output_dir, paste0("EWS_percelen_", Sys.Date(), ".gpkg")), delete_dsn = TRUE)

# ------------------------------------------------------------------
# 8. Visualisatie in Leaflet
# ------------------------------------------------------------------

layers <- list(
  EWS_kern = EWS_kern,
  EWS_percelen = EWS_percelen,
  dvw_indeling = dvw_indeling,
  dvw_percelen = dvw_percelen
)
layers_wgs <- lapply(layers, st_transform, crs = 4326)


if (interactive()) {
leaflet() %>%
  addProviderTiles("CartoDB.Positron") %>%
  
  # DVW-shapes
  addPolygons(data = layers_wgs$dvw_indeling, color = "#999999", weight = 1, fillOpacity = 0.2, group = "DVW Indeling") %>%
  addPolygons(data = layers_wgs$dvw_percelen, color = "#666666", weight = 1, fillOpacity = 0.2, group = "DVW Percelen") %>%
  
  # Kern: oud (blauw)
  addCircleMarkers(data = layers_wgs$EWS_kern[!layers$EWS_kern$nieuw, ],
                   radius = 4, stroke = FALSE, fillColor = "#3182bd", fillOpacity = 0.7, group = "EWS Kern") %>%
  # Kern: nieuw (donkergroen)
  addCircleMarkers(data = layers_wgs$EWS_kern[layers$EWS_kern$nieuw, ],
                   radius = 4, stroke = FALSE, fillColor = "#006400", fillOpacity = 0.9, group = "Nieuwe Kern") %>%
  
  # Percelen: oud (rood)
  addCircleMarkers(data = layers_wgs$EWS_percelen[!layers$EWS_percelen$nieuw, ],
                   radius = 4, stroke = TRUE, color = "#e41a1c", weight = 1, fillOpacity = 1, group = "EWS Percelen") %>%
  # Percelen: nieuw (lichtgroen)
  addCircleMarkers(data = layers_wgs$EWS_percelen[layers$EWS_percelen$nieuw, ],
                   radius = 4, stroke = TRUE, color = "#ADFF2F", weight = 1, fillOpacity = 1, group = "Nieuwe Percelen") %>%
  
  addLayersControl(
    overlayGroups = c("EWS Percelen", "Nieuwe Percelen", "EWS Kern", "Nieuwe Kern", "DVW Indeling", "DVW Percelen"),
    options = layersControlOptions(collapsed = FALSE)
  )
}