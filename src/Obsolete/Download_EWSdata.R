library(curl)
library(readr)
library(sf)
library(dplyr)

# Instellingen
base_url <- "https://alert.riparias.be/api/wfs/observations"
batch_size <- 10000
max_batches <- 1000
all_data <- list()
total_rows <- 0

cat("Start batch-download van RIPARIAS-observaties (CSV + sf)\n")
cat("Doel: max", batch_size * max_batches, "records in blokken van", batch_size, "\n\n")

for (i in 0:(max_batches - 1)) {
  offset <- i * batch_size
  cat(">>> Batch ", i + 1, ": ophalen van offset ", offset, "...\n", sep = "")
  
  url <- paste0(
    base_url,
    "?SERVICE=WFS",
    "&VERSION=2.0.0",
    "&REQUEST=GetFeature",
    "&TYPENAMES=observation",
    "&OUTPUTFORMAT=csv",
    "&LIMIT=", batch_size,
    "&OFFSET=", offset
  )
  
  tmp <- tempfile(fileext = ".csv")
  
  h <- new_handle()
  handle_setopt(h,
                timeout = 600,
                low_speed_time = 60,
                low_speed_limit = 10,
                failonerror = TRUE
  )
  
  success <- tryCatch({
    curl_download(url, tmp, mode = "wb", handle = h)
    TRUE
  }, error = function(e) {
    cat("!! Downloadfout: ", e$message, "\n")
    FALSE
  })
  
  if (!success) break
  
  file_size <- round(file.info(tmp)$size / 1024 / 1024, 2)
  cat("    Bestandsgrootte: ", file_size, " MB\n", sep = "")
  
  chunk <- tryCatch({
    read_csv(tmp, show_col_types = FALSE)
  }, error = function(e) {
    cat("!! Fout bij inlezen CSV (offset ", offset, "): ", e$message, "\n", sep = "")
    NULL
  })
  
  if (is.null(chunk) || nrow(chunk) == 0) {
    cat("==> Geen records meer na offset ", offset, ". Download afgerond.\n")
    break
  }
  
  cat("    Records in batch: ", nrow(chunk), "\n", sep = "")
  
  # Extractie van x/y uit 'SRID=3857;POINT(x y)'
  chunk <- chunk |>
    mutate(
      location_clean = gsub("SRID=3857;", "", location),
      x = as.numeric(sub("POINT\\(([^ ]+) ([^ ]+)\\)", "\\1", location_clean)),
      y = as.numeric(sub("POINT\\(([^ ]+) ([^ ]+)\\)", "\\2", location_clean))
    ) |>
    st_as_sf(coords = c("x", "y"), crs = 3857, remove = FALSE)
  
  total_rows <- total_rows + nrow(chunk)
  cat("    Totaal verzameld tot nu toe: ", total_rows, " records\n\n", sep = "")
  
  all_data[[length(all_data) + 1]] <- chunk
}

# Combineer en exporteer
if (length(all_data) > 0) {
  cat(">>> Alle batches verzamelen...\n")
  obs_all <- do.call(rbind, all_data)
  
  dir.create("data/input", showWarnings = FALSE, recursive = TRUE)
  st_write(obs_all, "data/input/ews_full.gpkg", delete_dsn = TRUE)
  
  cat("\nExport voltooid: ", nrow(obs_all), " records geschreven naar data/input/ews_full.gpkg\n")
} else {
  cat("Geen data verzameld. Bestand niet aangemaakt.\n")
}
