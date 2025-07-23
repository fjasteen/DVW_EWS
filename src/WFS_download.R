library(shiny)
library(leaflet)
library(sf)
library(httr)
library(jsonlite)
library(dplyr)

setwd("C:/Users/frederique_steen/Documents/GitHub/DVW_WFS/")

ui <- fluidPage(
  titlePanel("Vlaanderen Biodiversiteitskaart"),
  sidebarLayout(
    sidebarPanel(
      selectInput("scale", "Selecteer Schaal",
                  choices = c("Percelen", "Kerngebieden")),
      uiOutput("region_ui"),
      uiOutput("district_ui"),
      dateRangeInput("dateRange", "Selecteer Tijdsbestek", 
                     start = Sys.Date() - 30, end = Sys.Date()),
      actionButton("filter", "Data Filteren"),
      br(),
      textOutput("progress")
    ),
    mainPanel(
      leafletOutput("map"),
      downloadButton("downloadShape", "Exporteer als Shapefile"),
      downloadButton("downloadCSV", "Exporteer als CSV")
    )
  )
)

server <- function(input, output, session) {
  observeEvent(input$scale, {
    # Dynamische UI voor regio
    output$region_ui <- renderUI({
      selectInput("region", "Kies een Regio",
                  choices = c("Alle" = "alle", "aRW", "aRO", "aRC"))
    })
  })
  
  observeEvent(input$region, {
    # Dynamische UI voor district op basis van geselecteerde regio
    regio_shapes <- sf::st_read("./data/DVW_indeling.gpkg") # Vervang met jouw GeoPackage
    available_districts <- regio_shapes %>%
      filter(AFD == input$region) %>%
      pull(DSTRCT)
    
    output$district_ui <- renderUI({
      selectInput("district", "Kies een District", choices = available_districts)
    })
  })
  
  observeEvent(input$filter, {
    output$progress <- renderText({"Data ophalen..."})
    
    # Kies juiste shape op basis van schaal
    shape_file <- if (input$scale == "Percelen") "./data/DVW_percelen.gpkg" else "./data/DVW_indeling.gpkg"
    regio_shapes <- sf::st_read(shape_file)
    
    # Filter regio en district
    selected_region <- regio_shapes %>% filter(AFD == input$region)
    selected_district <- selected_region %>% filter(DSTRCT == input$district)
    
    # WFS-data ophalen
    wfs_url <- "https://alert.riparias.be/api/wfs/observations?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=observation&OUTPUTFORMAT=geojson"  # Vervang met echte URL
    query <- list(
      service = "WFS",
      request = "GetFeature",
      typename = "observation",
      outputFormat = "application/json"
    )
    response <- httr::GET(wfs_url, query = query)
    
    if (httr::status_code(response) == 200) {
      output$progress <- renderText({"Data succesvol opgehaald. Verwerken..."})
      data <- jsonlite::fromJSON(content(response, "text"))
      
      # Data omzetten naar sf-object
      sf_data <- sf::st_as_sf(data)
      
      # Data filteren op tijd, regio en district
      filtered_data <- sf_data %>%
        filter(observation_date >= input$dateRange[1] & 
                 observation_date <= input$dateRange[2]) %>%
        filter(sf::st_intersects(geometry, selected_district, sparse = FALSE))
      
      # Kaart visualiseren
      output$map <- renderLeaflet({
        leaflet(filtered_data) %>%
          addTiles() %>%
          addCircleMarkers(~st_coordinates(geometry)[,1], ~st_coordinates(geometry)[,2], 
                           popup = ~species_scientific_name)
      })
      
      # Exporteren van bestanden
      output$downloadShape <- downloadHandler(
        filename = function() { "filtered_data.shp" },
        content = function(file) {
          sf::st_write(filtered_data, file)
        }
      )
      
      output$downloadCSV <- downloadHandler(
        filename = function() { "filtered_data.csv" },
        content = function(file) {
          write.csv(filtered_data, file, row.names = FALSE)
        }
      )
      
      output$progress <- renderText({"Verwerking voltooid!"})
    } else {
      output$progress <- renderText({"Fout bij ophalen van data."})
    }
  })
}

shinyApp(ui = ui, server = server)
