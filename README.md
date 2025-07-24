# DVW_WFS

Dit script automatiseert het ophalen van waarnemingsdata van RIPARIAS via WFS (in CSV-formaat), filtert deze op basis van de prioritaire exotenlijst (via GBIF), 
voert intersecties uit met shapefiles van De Vlaamse Waterweg (DVW), en visualiseert de resultaten in een interactieve kaart. 
Resultaten worden opgeslagen in GeoPackage-bestanden voor gebruik in ArcGIS of QGIS. Via GitHub Actions kan deze workflow periodiek uitgevoerd worden, 
waarbij de gegenereerde bestanden automatisch geüpload worden naar een publiek toegankelijke repository.
 
DVW_WFS/
├── .git/
├── .gitignore
├── README.md
├── DVW_WFS.Rproj
├── data/
│   ├── input/
│   │   ├── DVW_indeling.gpkg
│   │   └── DVW_percelen.gpkg
│   └── output/
│       ├── EWS_kern.gpkg
│       └── EWS_percelen.gpkg
├── src/
│   └── riparias_download.R
├── .github/
│   └── workflows/
│       └── wfs-update.yml