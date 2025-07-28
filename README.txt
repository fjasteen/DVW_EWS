# DVW GBIF Downloader & Monitor

Dit project automatiseert het downloaden, opschonen en analyseren van GBIF-occurrence-data voor de DVW-prioritaire soortenlijst (inclusief *Zizania latifolia*) in België. Het script vergelijkt nieuwe downloads met eerdere datasets en labelt nieuwe waarnemingen.  

## Functionaliteit

- Downloadt GBIF-occurrence-data op basis van de DVW-checklist.  
- Filtert op:
  - België (country = BE)
  - Records met coördinaten
  - Jaar ≥ 2013  
- Intersecteert waarnemingen met DVW-indeling en DVW-percelen (ruimtelijke selectie).  
- Labelt nieuwe records (niet aanwezig in vorige downloads).  
- Schrijft resultaten weg als GeoPackages en logt metadata in een CSV-logbestand.  
- Visualiseert resultaten interactief met Leaflet.  

---

## Vereisten

### Software

- R (≥ 4.2)
- Packages: tidyverse, here, rgbif, lubridate, sf, leaflet

Installeer afhankelijkheden in R met:  
install.packages(c("tidyverse", "here", "rgbif", "lubridate", "sf", "leaflet"))

### GBIF API-credentials (.Renviron)

Om de GBIF API te kunnen gebruiken, maak je een bestand met de naam `.Renviron` aan in de projectfolder. Dit bestand bevat je GBIF-gebruikersgegevens en mag niet openbaar gedeeld worden.  

Inhoud van `.Renviron`:  
GBIF_USER=je_gebruikersnaam  
GBIF_PWD=je_wachtwoord  
GBIF_EMAIL=je_email@adres.com  

Belangrijk: zet `.Renviron` altijd in `.gitignore` zodat dit bestand niet op GitHub verschijnt.

---

## Projectstructuur

De verwachte projectstructuur is:  

project/  
├─ .Renviron  
├─ gbif_download_dvw.R          (hoofdscript)  
├─ data/  
│  ├─ input/  
│  │  ├─ DVW_indeling.gpkg      (DVW-indelingspolygonen)  
│  │  ├─ DVW_percelen.gpkg      (DVW-percelenpolygonen)  
│  │  ├─ vernacular_names.csv   (koppeling taxonKey ↔ vernaculaire naam)  
│  │  └─ raw/                   (tijdelijke downloadbestanden – worden gewist)  
│  ├─ output/  
│  │  ├─ gbif_download_log.csv  (metadata van alle downloads)  
│  │  ├─ EWS_kern_YYYY-MM-DD.gpkg  
│  │  └─ EWS_percelen_YYYY-MM-DD.gpkg  

---
