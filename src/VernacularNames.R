library(tidyverse)
library(rgbif)

# species_keys bestaat al (vector met keys)

vernacular_lookup <- map_df(species_keys, function(key) {
  vn <- tryCatch(
    name_usage(key = key, data = "vernacularNames")$data,
    error = function(e) NULL
  )
  
  if (is.null(vn) || nrow(vn) == 0) return(NULL)
  
  vn %>%
    filter(language == "nld") %>%                  # alleen NL namen
    select(speciesKey = taxonKey, vernacularName)  # speciesKey en naam
})

# Toon resultaten
print(nrow(vernacular_lookup))
head(vernacular_lookup, 20)

# Als je deze wilt koppelen aan species_list
species_with_nl <- species_list %>%
  left_join(vernacular_lookup, by = c("nubKey" = "speciesKey"))

# Resultaat bekijken
species_with_nl %>%
  select(scientificName, vernacularName)
