#' Functions for Dust Emission Modelling using AERO
#'


scaled.gap<-function(gap.tall, height.tall, out){
  #Calculate gaps by breaks
  gap<-gap.cover(gap.tall,
                 tall=TRUE,
                 type="canopy",
                 breaks=seq(from=0, to=1000, length.out=400))
  #Calculate mean maximum height for each plot
  height<-mean.height(lpi.height.tall = lpi.height.tall,
                      type = "max",
                      omit.zero = TRUE)
  #Calculate the total number of gaps in each plot
  gap.probability<-gap %>% dplyr::group_by(PrimaryKey) %>%
    dplyr::summarise(total.n=sum(n)) %>%merge(gap,., allow.cartesian=TRUE) %>%
      #Calculate the probability of gaps for each gap interval within each plot
    dplyr::group_by(PrimaryKey, Gap.Class)%>%
    dplyr::summarise(probability=n/total.n)

  #Calculate the scaled gap for each gap interval, this is each gap class divided by the mean maximum height
    #Rename gap intervals so they are numeric
    gap$interval.value<-gsub(pattern="\\[|\\,.+$", x=gap$Gap.Class, replacement="") %>% as.numeric()
    scaled.gap<-merge(gap, height, allow.cartesian=TRUE) %>% dplyr::group_by(PrimaryKey, Gap.Class) %>%
    dplyr::summarise(scaled.gap=interval.value/max.height)

    #Merge the scaled gap and gap probability
    gap.output<-merge(scaled.gap, gap.probability, allow.cartesian=TRUE)


  }


surface.soil.texture<-function(filepath,
                               gdb, soil.texture.file){
  library(arcgisbinding)
  arcgisbinding::arc.check_product()

  #read in soil texture by class look up table
  texture.lut<-read.csv(soil.texture.file, fileEncoding="UTF-8-BOM")

  #Read in soil pit data
  soil.pit.horizons<-read.geodatabase(filepath = filepath, gdb=gdb, feature.name = "tblSoilPitHorizons")

  #merge soil texture classes with soil texture data
  soil.surface.texture<-merge(soil.pit.horizons, texture.lut, by.x="Texture", by.y="abbreviation")

  #Subset soil by surface soil horizon and the Primary Key and Texture Class fields only
  soil.surface.texture<-soil.surface.texture[soil.surface.texture$HorizonDepthUpper==0,c("PrimaryKey", "texture_class")]

  #Return soil texture
  return(soil)
}


aero.coordinates.bare.soil<-function(filepath, gdb){
  library(arcgisbinding)
  arcgisbinding::arc.check_product()

  #Read in tblPlots
  plots<-read.geodatabase(filepath = filepath, gdb=gdb, feature.name = "SV_IND_TERRESTRIALAIM")

  coordinates.bare.soil<-plots[,c("PrimaryKey","Latitude", "Longitude", "BareSoilCover_FH")]

  return(coordinates.bare.soil)
}


#Write out files

write.to.aero<-function (out, gap.output, coordinates.bare.soil, soil.surface.texture,
                         folder.location="C:\\Users\\mgalloza\\Desktop\\NICK\\BLM_BATCH_example\\BLM_Data\\AllTerrADat\\", #location of files on computer with AERO
                         combo.name="All.TerrADat"){

  #Find out which plots have gap, bare soil, and surface texture data
  common.PK<-Reduce(intersect,(list (unique(gap.output$PrimaryKey),unique(coordinates.bare.soil$PrimaryKey),unique(soil.surface.texture$PrimaryKey) )))

  #Write Scaled Gap txt files
  lapply(common.PK,
                function(X) write.table(gap.output[gap.output$PrimaryKey==X,c("scaled.gap","probability")],
                                        file = paste(out,X,".txt",sep=""),
                                        col.names = F, row.names = F, sep="\t"))


  #Write Ini and Combofiles
  combo<-NULL
  #Write the ini files out to folder and compile the list of files for the combo .bat files
  combo<-lapply(common.PK,
         function(p){cat(file=paste(out, p,".ini", sep=""),
                        "[INPUT_VALUES]",
                        paste("wind_location:", coordinates.bare.soil$Latitude[coordinates.bare.soil$PrimaryKey==p],
                              coordinates.bare.soil$Longitude[coordinates.bare.soil$PrimaryKey==p], sep=" "),
                        paste("soil_type: " , soil.surface.texture$texture_class[soil.surface.texture$PrimaryKey==p], sep=""),
                        paste("veg_cover_fraction: ", (100-coordinates.bare.soil$BareSoilCover_FH[coordinates.bare.soil$PrimaryKey==p])/100, sep=""),
                        paste("gap_obsv: ", folder.location, p, ".txt", sep=""),
                        "[METHOD_REQUESTS]","[OUTPUTS]", "horizontal_flux_total", "vertical_flux", "_vflux_bins","soil_type","_vflux_psd",
                        sep="\n", append=F)

         combo<-c(combo,paste(p, ".ini"," ^", sep="" ))
         return(combo)})

  #Write out the comb.bat file
  cat(file=paste(out, combo.name,".bat", sep=""),
      "\n python -m WEME.driver.combo -v ^",
      paste("    --combos ",combo[1], sep="") ,
      paste("             ",combo[2:length(combo)], sep=""),
      "    --cases blm_case.ini ^",
      "    --output blm_terradat.html",
      sep="\n", append=F)

}


